// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "./RewardsDistributor.sol";

// Uncomment this line to use console.log
// import "hardhat/console.sol";

string constant NAME = "CygnusNetwork";
string constant SYMBOL = "CygN";

uint256 constant INITIAL_SUPPLY = 500_000_000 * 10 ** 18;

uint16 constant BUY_TAX_LIQUIDIY = 1000; // 10%
uint16 constant BUY_TAX_TEAM = 500; // 5%
uint16 constant BUY_TAX_REWARD = 500; // 5%

uint16 constant SELL_TAX_LIQUIDIY = 1000; // 10%
uint16 constant SELL_TAX_TEAM = 500; // 5%
uint16 constant SELL_TAX_REWARD = 500; // 5%

uint256 constant TAX_BASE = 10000;

uint256 constant MAX_TAX = 2000; // 20%

uint256 constant DAY = 1 days;

struct Tax {
    uint16 liquidity;
    uint16 team;
    uint16 rewards;
}

interface IUniFactory {
    function createPair(
        address tokenA,
        address tokenB
    ) external returns (address pair);
}

contract CygnusNetworkToken is ERC20Permit, ERC20Votes, Ownable, HolderRewards {
    using SafeERC20 for IERC20;

    Tax public buyTax = Tax(BUY_TAX_LIQUIDIY, BUY_TAX_TEAM, BUY_TAX_REWARD); // 6 bytes
    Tax public sellTax = Tax(SELL_TAX_LIQUIDIY, SELL_TAX_TEAM, SELL_TAX_REWARD); // 6 bytes

    address payable public liquidityHolder; // 20 bytes
    address payable public teamHolder; // 20 bytes
    bool public taxEnabled = false;

    IUniFactory public immutable uniFactory; // 20 bytes
    IUniswapV2Router02 public immutable uniRouter; // 20 bytes
    address public immutable weth; // 20 bytes
    address public immutable uniPair; // 20 bytes

    mapping(address => bool) public isExcludedFromFee;

    mapping(address => bool) public isPair;

    uint256 public liquidityReserves;
    uint256 public rewardsReserves;
    uint256 public miniBeforeLiquify;

    event TaxEnabled(bool enabled);
    event ExeededFromFee(address account, bool excluded);
    event Pair(address pair, bool isPair);
    event RewardsHolder(address oldHolder, address holder);
    event TEAMHolder(address oldHolder, address holder);
    event LiquidityHolder(address oldHolder, address holder);
    event SellTaxChanged(uint16 liquidity, uint16 team, uint16 rewards);
    event BuyTaxChanged(uint16 liquidity, uint16 team, uint16 rewards);
    event ExcludedFromDailyVolume(address account, bool excluded);
    event MiniBeforeLiquifyChanged(uint256 miniBeforeLiquifyArg);

    constructor(
        // to allow for easy testing/deploy on behalf of someone else
        address ownerArg,
        address payable teamHolderArg,
        address payable liquidityHolderArg,
        IUniswapV2Router02 uniswapV2RouterArg,
        IUniFactory uniswapV2FactoryArg
    ) ERC20(NAME, SYMBOL) Ownable(ownerArg) ERC20Permit("") {
        _mint(ownerArg, INITIAL_SUPPLY);

        require(
            teamHolderArg != address(0),
            "CygnusNetwork: team holder is the zero address"
        );
        teamHolder = teamHolderArg;
        require(
            liquidityHolderArg != address(0),
            "CygnusNetwork: liquidity holder is the zero address"
        );
        liquidityHolder = liquidityHolderArg;

        uniRouter = uniswapV2RouterArg;
        uniFactory = uniswapV2FactoryArg;

        weth = uniswapV2RouterArg.WETH();

        // Create a uniswap pair for this new token
        uniPair = uniswapV2FactoryArg.createPair(address(this), weth);

        // approve token transfer to cover all future transfereFrom calls
        _approve(address(this), address(uniswapV2RouterArg), type(uint256).max);

        isPair[uniPair] = true;

        excludedFromRewards[uniPair] = true;

        isExcludedFromFee[address(this)] = true;
        excludedFromRewards[address(this)] = true;

        isExcludedFromFee[ownerArg] = true;
    }

    receive() external payable {
        // only receive from router
        require(msg.sender == address(uniRouter), "Invalid sender");
    }

    /**
     * @notice Transfers tokens to a recipient
     * @param recipient address to send the tokens to
     * @param amount  amount of tokens to send
     */
    function transfer(
        address recipient,
        uint256 amount
    ) public virtual override returns (bool) {
        _customTransfer(_msgSender(), recipient, amount);
        return true;
    }

    /**
     * @notice Transfers tokens from a sender to a recipient (requires approval)
     * @param sender address to send the tokens from
     * @param recipient address to send the tokens to
     * @param amount  amount of tokens to send
     */
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public virtual override returns (bool) {
        uint256 allowance = allowance(sender, _msgSender());
        require(amount <= allowance, "Transfer amount exceeds allowance");

        // overflow is checked above
        unchecked {
            // decrease allowance if not max approved
            if (allowance < type(uint256).max)
                _approve(sender, _msgSender(), allowance - amount, true);
        }

        _customTransfer(sender, recipient, amount);

        return true;
    }

    function _customTransfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal {
        if (sender != uniPair) _liquify();

        if (
            !taxEnabled ||
            isExcludedFromFee[sender] ||
            isExcludedFromFee[recipient] ||
            (!isPair[recipient] && !isPair[sender]) ||
            inswap == 1
        ) {
            _normalTransfer(sender, recipient, amount);
        } else {
            Tax memory tax = isPair[recipient] ? buyTax : sellTax;

            // buy
            uint256 teamTax = (amount * tax.team) / TAX_BASE;
            uint256 rewardsTax = (amount * tax.rewards) / TAX_BASE;
            uint256 liquidityTax = (amount * tax.liquidity) / TAX_BASE;

            if (rewardsTax > 0) {
                rewardsReserves += rewardsTax;
                _normalTransfer(sender, address(this), rewardsTax);
            }
            if (teamTax > 0) _normalTransfer(sender, teamHolder, teamTax);

            _normalTransfer(
                sender,
                recipient,
                amount - teamTax - rewardsTax - liquidityTax
            );

            if (liquidityTax > 0) {
                liquidityReserves += liquidityTax;
                _normalTransfer(sender, address(this), liquidityTax);
            }
        }

        _massProcess();
    }

    function _normalTransfer(address from, address to, uint256 value) internal {
        if (from == address(0)) {
            revert ERC20InvalidSender(address(0));
        }
        if (to == address(0)) {
            revert ERC20InvalidReceiver(address(0));
        }
        _update(from, to, value);

        _updateShare(from);
        _updateShare(to);
    }

    function _update(
        address from,
        address to,
        uint256 amount
    ) internal override(ERC20, ERC20Votes) {
        super._update(from, to, amount);
    }

    function nonces(
        address owner
    ) public view virtual override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }

    /**
     * @notice mass claim for all shareholder only if maxAutoProcessGas > 0
     */
    function _massProcess() internal {
        if (inswap == 0 && rewardsUpdated == 1 && maxAutoProcessGas > 0) {
            batchProcessClaims(
                gasleft() > maxAutoProcessGas
                    ? maxAutoProcessGas
                    : (gasleft() * 80) / 100
            );
            rewardsUpdated = 0;
        }
    }

    /**
     * @notice update
     * @param wallet address to update share
     */
    function _updateShare(address wallet) internal {
        if (!excludedFromRewards[wallet])
            _setShare(
                wallet,
                balanceOf(wallet) > minShareForRewards ? balanceOf(wallet) : 0
            );
    }

    function includeInRewards(address user) external onlyOwner {
        require(excludedFromRewards[user], "Distributor: not excluded");

        _updateUserShares(user, balanceOf(user));
        excludedFromRewards[user] = false;
        emit IncludedInRewards(user, true);
    }

    /**
     * @notice Enable or disable taxes
     * @param taxEnabledArg true to enable tax, false to disable
     */
    function setTaxEnabled(bool taxEnabledArg) public onlyOwner {
        require(taxEnabled != taxEnabledArg, "CygnusNetwork: already set");
        taxEnabled = taxEnabledArg;

        emit TaxEnabled(taxEnabledArg);
    }

    /**
     * @notice Sets the minimum amount of tokens that must be in the contract before liquifying
     * @param miniBeforeLiquifyArg  The minimum amount of tokens that must be in the contract before liquifying
     */
    function setMiniBeforeLiquify(
        uint256 miniBeforeLiquifyArg
    ) public onlyOwner {
        require(
            miniBeforeLiquifyArg != miniBeforeLiquify,
            "CygnusNetwork: already set"
        );
        miniBeforeLiquify = miniBeforeLiquifyArg;

        emit MiniBeforeLiquifyChanged(miniBeforeLiquifyArg);
    }

    /**
     * @notice sets whether an address is excluded  from fees or not
     * @param account The address to exclude/include from fees
     * @param excluded  true to exclude, false to include
     */
    function setExcludedFromFee(
        address account,
        bool excluded
    ) public onlyOwner {
        require(
            isExcludedFromFee[account] != excluded,
            "CygnusNetwork: already set"
        );
        isExcludedFromFee[account] = excluded;

        emit ExeededFromFee(account, excluded);
    }

    /**
     *  @notice declare if an address is an lp pair or not
     * @param pair address of the LP Pool
     * @param isPairArg  true if the address is a pair, false otherwise
     */
    function setPair(address pair, bool isPairArg) public onlyOwner {
        require(isPair[pair] != isPairArg, "CygnusNetwork: already set");
        isPair[pair] = isPairArg;

        emit Pair(pair, isPairArg);
    }

    /**
     * @dev Sets the team holder address
     * @param _teamHolder The address of the team holder
     */
    function setTeamHolder(address payable _teamHolder) public onlyOwner {
        require(_teamHolder != teamHolder, "CygnusNetwork: already set");
        require(_teamHolder != address(0), "CygnusNetwork: zero address");
        teamHolder = _teamHolder;

        emit TEAMHolder(teamHolder, _teamHolder);
    }

    /**
     * @dev Sets the liquidity holder address
     * @param _liquidityHolder The address of the liquidity holder
     */
    function setLiquidityHolder(
        address payable _liquidityHolder
    ) public onlyOwner {
        require(
            _liquidityHolder != liquidityHolder,
            "CygnusNetwork: already set"
        );
        require(_liquidityHolder != address(0), "CygnusNetwork: zero address");
        liquidityHolder = _liquidityHolder;
        emit LiquidityHolder(liquidityHolder, _liquidityHolder);
    }

    /**
     * @dev Changes the tax on buys
     * @param _liquidity liquidity tax in basis points
     * @param _team team tax in basis points
     * @param _rewards rewards tax in basis points
     */
    function setSellTax(
        uint16 _liquidity,
        uint16 _team,
        uint16 _rewards
    ) public onlyOwner {
        require(
            _liquidity + _team + _rewards <= MAX_TAX,
            "CygnusNetwork: tax too high"
        );
        sellTax = Tax(_liquidity, _team, _rewards);

        emit SellTaxChanged(_liquidity, _team, _rewards);
    }

    /**
     * @dev Changes the tax on sells
     * @param _liquidity liquidity tax in basis points
     * @param _team team tax in basis points
     * @param _rewards rewards tax in basis points
     */
    function setBuyTax(
        uint16 _liquidity,
        uint16 _team,
        uint16 _rewards
    ) public onlyOwner {
        require(
            _liquidity + _team + _rewards <= MAX_TAX,
            "CygnusNetwork: tax too high"
        );
        buyTax = Tax(_liquidity, _team, _rewards);

        emit BuyTaxChanged(_liquidity, _team, _rewards);
    }

    /**
     * @notice Burns tokens from the caller
     * @param amount amount of tokens to burn
     */
    function burn(uint256 amount) public {
        _burn(msg.sender, amount);
    }

    /**
     * @notice Recovers lost tokens or ETH, doesn't include the liquidity reserves
     * @param tokenAddress address of the token to recover
     */
    function recoverLostTokens(address tokenAddress) public onlyOwner {
        if (tokenAddress != address(this)) {
            uint256 tokenAmount = tokenAddress != address(0)
                ? IERC20(tokenAddress).balanceOf(address(this))
                : address(this).balance - totalPending();

            if (tokenAmount > 0 && tokenAddress != address(0)) {
                IERC20(tokenAddress).safeTransfer(msg.sender, tokenAmount);
            } else if (tokenAmount > 0) {
                (bool success, ) = payable(msg.sender).call{value: tokenAmount}(
                    ""
                );
                require(success, "Failed to send Ether");
            }
        } else {
            uint256 tokenAmount = balanceOf(address(this)) - liquidityReserves;
            _normalTransfer(address(this), msg.sender, tokenAmount);
        }
    }

    // using uint256 is cheaper than using bool
    // because there will be no extra work to read it
    // sunce when used we always return it back to 0
    // it will trigger a refund
    uint256 inswap = 0;

    // if we added any rewards we set this to 1
    // if this is 1 we trigger batch process
    // if we batch process we set this back to 0
    uint256 rewardsUpdated = 0;

    /**
     * @notice creates lp from the liquidity reserves
     */
    function liquify() external onlyOwner {
        _liquify();
    }

    function _liquify() private {
        if (inswap == 1) return;

        if (liquidityReserves > miniBeforeLiquify) {
            inswap = 1;
            // get reserves from pair
            (uint256 reserves0, uint256 reserves1, ) = IUniswapV2Pair(uniPair)
                .getReserves();

            // Check Uniswap library sortTokens (token0 < token1)
            uint256 tokenReserves = address(this) < weth
                ? reserves0
                : reserves1;

            // swap capped at 10% of the reserves which is tecnically 5% because we only swap half
            uint256 maxToSwap = (tokenReserves * 10) / 100;

            uint256 toswap = liquidityReserves > maxToSwap
                ? maxToSwap
                : liquidityReserves;

            uint256 half = toswap / 2;
            // avoids precision loss
            uint256 otherHalf = toswap - half;

            uint256 balanceBefore = address(this).balance;

            _swapTokensForEth(half);

            uint256 newBalance = address(this).balance - balanceBefore;

            _addLiquidity(otherHalf, newBalance);

            liquidityReserves -= toswap;
            inswap = 0;
        }

        if (rewardsReserves > miniBeforeLiquify) {
            inswap = 1;

            uint256 balance = address(this).balance;

            (uint256 reserves0, uint256 reserves1, ) = IUniswapV2Pair(uniPair)
                .getReserves();

            // Check Uniswap library sortTokens (token0 < token1)
            uint256 tokenReserves = address(this) < weth
                ? reserves0
                : reserves1;
            // at max swap
            uint256 maxToSwap = (tokenReserves * 10) / 100;

            uint256 toswap = rewardsReserves > maxToSwap
                ? maxToSwap
                : rewardsReserves;

            _swapTokensForEth(toswap);

            balance = address(this).balance - balance;

            // update
            _addRewards(balance);

            rewardsUpdated = 1;

            rewardsReserves -= toswap;

            inswap = 0;
        }
    }

    function _swapTokensForEth(uint256 tokenAmount) internal {
        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = weth;

        // make the swap safely, do not revert if swap fails
        try
            uniRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(
                tokenAmount,
                0, // accept any amount of ETH
                path,
                address(this),
                block.timestamp
            )
        {} catch {}
    }

    function _addLiquidity(uint256 tokenAmount, uint256 ethAmount) internal {
        // do not revert if addlp fails
        try
            uniRouter.addLiquidityETH{value: ethAmount}(
                address(this),
                tokenAmount,
                0,
                0,
                liquidityHolder,
                block.timestamp
            )
        {} catch {}
    }
}
