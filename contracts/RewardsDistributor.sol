// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "@openzeppelin/contracts/access/Ownable.sol";

// import "hardhat/console.sol";

uint256 constant DEBT_DENOMINATOR = 1e36;

struct ShareHolder {
    uint256 shares;
    uint256 rewardDebt;
    uint256 claimed;
    uint256 pending;
}

/**
 * @notice This contract is similar to masterchef contract except it distributed the eth deposited
 * and instead of a stake we use shares which is the same as the user balance
 */

abstract contract HolderRewards is Ownable {
    uint256 public minShareForRewards;

    uint256 public maxAutoProcessGas = 50000;

    uint256 public accPerShare; // Accumulated per share, times DEBT_DENOMINATOR.
    uint256 public totalShares; // total number of shares
    uint256 public totalClaimed; // total amount claimed
    uint256 public totalRewardsDebt; // total amount claimed

    uint256 private _reservedRewards = 0; // when no one is a holder we save the rewards here

    // Maybe EnumerableSet? but it's the same only simpler
    mapping(address => ShareHolder) shareHolders;
    address[] public allShareHolders;
    mapping(address => uint256) public indexOfShareHolders;

    uint256 private _lastProccessedIndex = 1;

    mapping(address => bool) public excludedFromRewards;

    // events
    event Claimed(address indexed claimer, uint256 indexed amount);
    event RewardsAdded(uint256 indexed amount);
    event ShareUpdated(
        address indexed shareHolder,
        uint256 indexed sharesAmount
    );

    event IncludedInRewards(address indexed shareHolder, bool included);

    constructor() {
        allShareHolders.push(address(0)); // use the index zero for address zero
    }

    /**
     * @notice returns the amount of rewards pending for the givven address
     * @param user address to get pending rewards of
     */
    function pending(address user) public view returns (uint256 pendingAmount) {
        ShareHolder storage userData = shareHolders[user];
        pendingAmount =
            ((userData.shares * (accPerShare)) / DEBT_DENOMINATOR) -
            userData.rewardDebt;
    }

    /**
     * @notice returns the total amount of pending rewards for all users
     */
    function totalPending() public view returns (uint256) {
        return
            ((accPerShare * (totalShares)) / (DEBT_DENOMINATOR)) -
            (totalRewardsDebt);
    }

    /**
     * @notice any user with a balance less than this will not receive rewards
     * @param minBalance minimum balance to be eligible for rewards
     */
    function setMinSharePerRewards(uint256 minBalance) external onlyOwner {
        require(minBalance <= 50_000 * 10 ** 18, "can't set the min more than 50k");
        minShareForRewards = minBalance;
    }

    /**
     * @notice sets the max amount of gas spent on batch claiming
     * set this to a reasonable amount to keep the transaction fees reasonable
     * @param maxGas max amount of gas
     */
    function setProcessingGasLimit(uint256 maxGas) external onlyOwner {
        maxAutoProcessGas = maxGas;
    }

    /**
     * @notice this user won;t receive any rewards no matter what his balance is
     * @param user address to be excluded from rewards
     */
    function excludeFromRewards(address user) external onlyOwner {
        _excludeFromRewards(user);
    }

    /** 
        @dev claim pending rewards for user
        can be called by anyone but only user
        can receive the reward
        @param user address to claim for 
    */
    function claimPending(address user) public {
        ShareHolder storage userData = shareHolders[user];

        uint256 pendingAmount = ((userData.shares * accPerShare) /
            DEBT_DENOMINATOR) - userData.rewardDebt;

        if (pendingAmount <= 0) return;


        emit Claimed(user, pendingAmount);

        userData.claimed = userData.claimed + pendingAmount;
        totalClaimed = totalClaimed + pendingAmount;

        totalRewardsDebt = totalRewardsDebt - userData.rewardDebt;
        userData.rewardDebt =
            (userData.shares * accPerShare) /
            DEBT_DENOMINATOR;
        totalRewardsDebt = totalRewardsDebt + userData.rewardDebt;

        (bool sent, ) = payable(user).call{value: pendingAmount}("");
        //if !sent means probably the receiver is a non payable address
        if (!sent) {
            // add pending amount to global shares to prevent loss of ETH
            _addRewards(pendingAmount);
        }
    }

    /**
     * @notice This function will manually claim for all shareholders
     * @param gas amount of gas to spend on the batch claim
     */
    function batchProcessClaims(uint256 gas) public {
        if (gasleft() < gas) return;
        uint256 gasUsed = 0;
        uint256 gasLeft = gasleft();
        uint256 iterations = 1; // index 0 is ocupied by address(0)

        // we
        while (gasUsed < gas && iterations < allShareHolders.length) {
            claimPending(allShareHolders[_lastProccessedIndex]);
            gasUsed = (gasUsed + gasLeft) - gasleft();
            gasLeft = gasleft();
            _incrementLastProccessed();
            iterations++;
        }
    }

    /**
        returns information about the share holder
        */
    function shareHolderInfo(
        address user
    ) external view returns (ShareHolder memory) {
        ShareHolder storage userData = shareHolders[user];
        return
            ShareHolder(
                userData.shares, // How many tokens the user is holding.
                userData.rewardDebt, // see @masterChef contract for more details
                userData.claimed,
                pending(user)
            );
    }

    function holders() external view returns (uint256) {
        return allShareHolders.length;
    }

    /**
     * @notice
     * @param user adress to exclude
     */
    function _excludeFromRewards(address user) internal {
        require(excludedFromRewards[user], "Distributor: already excluded");

        uint256 amountPending = pending(user);
        // update this user's shares to 0
        _updateUserShares(user, 0);
        // distribute his pending share to all shareholders
        if (amountPending > 0) _addRewards(amountPending);
        excludedFromRewards[user] = true;
        emit IncludedInRewards(user, false);
    }

    /**
        updates the accumulatedPerShare amount based on the new amount and total shares
    */
    function _addRewards(uint256 amount) internal {
        // prevent division by zero
        if (totalShares == 0) {
            _reservedRewards = _reservedRewards - (amount);
            return;
        }
        accPerShare =
            accPerShare +
            ((amount * DEBT_DENOMINATOR) / totalShares) +
            ((_reservedRewards * DEBT_DENOMINATOR) / totalShares);

        _reservedRewards = 0;
        emit RewardsAdded(amount);
    }

    /**
     * @dev this function claims the rewards then sets the share
     * if you do not want to claim check _updateUserShares
     * @param user address of user who's share to set
     * @param amount user's share (balance)
     */
    function _setShare(address user, uint256 amount) internal {
        if (excludedFromRewards[user]) return;

        ShareHolder storage userData = shareHolders[user];

        // pay any pending rewards
        if (userData.shares > 0) claimPending(user);
        // update total shares
        _updateUserShares(user, amount);
    }

    /**
     * @dev this function does not claim pening rewards it wipes them out
     * you should take care of the pending rewards before calling this function
     * @param user user who's share is to be updated
     * @param amount amount/share probably the balance
     */
    function _updateUserShares(address user, uint256 amount) internal {
        ShareHolder storage userData = shareHolders[user];
        totalShares = (totalShares - userData.shares) + (amount);
        totalRewardsDebt = totalRewardsDebt - userData.rewardDebt;
        userData.shares = amount;
        userData.rewardDebt =
            (userData.shares * accPerShare) /
            (DEBT_DENOMINATOR);
        totalRewardsDebt = totalRewardsDebt + (userData.rewardDebt);

        if (userData.shares > 0 && indexOfShareHolders[user] == 0) {
            // add this shareHolder to array
            allShareHolders.push(user);

            indexOfShareHolders[user] = allShareHolders.length - 1;
        } else if (userData.shares == 0 && indexOfShareHolders[user] != 0) {
            // remove this share holder from array
            uint256 index = indexOfShareHolders[user];

            allShareHolders[index] = allShareHolders[
                allShareHolders.length - 1
            ];

            indexOfShareHolders[
                allShareHolders[allShareHolders.length - 1]
            ] = index;

            allShareHolders.pop();

            indexOfShareHolders[user] = 0;
        }
        emit ShareUpdated(user, amount);
    }

    function _incrementLastProccessed() internal {
        _lastProccessedIndex++;
        if (_lastProccessedIndex >= allShareHolders.length)
            _lastProccessedIndex = 1;
    }
}
