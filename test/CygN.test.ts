import { ethers } from "hardhat";
import { expect } from "chai";

import {
  CygnusNetworkToken,
  CygnusNetworkToken__factory,
} from "../typechain-types";

const wethJson = require("@uniswap/v2-periphery/build/WETH9.json");
import uniswapFactory from "@uniswap/v2-core/build/UniswapV2Factory.json";
import uniswapRouter from "@uniswap/v2-periphery/build/UniswapV2Router02.json";
import uniswapPair from "@uniswap/v2-core/build/UniswapV2Pair.json";
import { Contract, ContractFactory } from "ethers";

const creaditEthTOAdress = async (address: string) => {
  await ethers.provider.send("hardhat_setBalance", [
    address,
    "0x" + ethers.parseEther("1000").toString(16), // 100 ETH
  ]);
};

const INITIAL_SUPPLY = 500_000_000n * 10n ** 18n;

const TAX_DENOMINATOR = 10000n;

const SELL_TAX = {
  liquidity: 1000n,
  team: 500n,
  rewards: 500n,
};

const BUY_TAX = {
  liquidity: 1000n,
  team: 500n,
  rewards: 500n,
};

const VALID_TAX = {
  liquidity: 666n,
  team: 666n,
  rewards: 666n,
};

const badTax = {
  liquidity: 1000n,
  team: 751n,
  rewards: 750n,
};

describe("CygN", () => {
  let weth: Contract;
  let uniFactory: Contract;
  let uniRouter: Contract;
  let cygn: CygnusNetworkToken;
  let pairAddress: string;

  before(async function () {
    const [owner, rewards, autoLP, team] = await ethers.getSigners();

    const UniswapV2Factory = await ethers.getContractFactory(
      uniswapFactory.abi,
      uniswapFactory.bytecode
    );
    uniFactory = (await UniswapV2Factory.deploy(owner.address)) as Contract;
    await uniFactory.waitForDeployment();

    const WETH9 = (await ethers.getContractFactory(
      wethJson.abi,
      wethJson.bytecode
    )) as ContractFactory;

    weth = (await WETH9.deploy()) as Contract;
    await weth.waitForDeployment();

    const UniswapV2Router02 = await ethers.getContractFactory(
      uniswapRouter.abi,
      uniswapRouter.bytecode
    );

    uniRouter = (await UniswapV2Router02.deploy(
      await uniFactory.getAddress(),
      await weth.getAddress()
    )) as Contract;

    await uniRouter.waitForDeployment();

    const CygnusNetworkFactory =
      await ethers.getContractFactory("CygnusNetworkToken");

    cygn = await CygnusNetworkFactory.deploy(
      owner.address,
      autoLP.address,
      team.address,
      await uniRouter.getAddress(),
      await uniFactory.getAddress()
    );

    cygn = await cygn.waitForDeployment();

    pairAddress = await uniFactory.getPair(
      await cygn.getAddress(),
      await weth.getAddress()
    );

    const signers = await ethers.getSigners();

    // credit eth to each signer
    for (let i = 0; i < signers.length; i++) {
      await creaditEthTOAdress(signers[i].address);
    }
  });

  it("should have the correct taxes", async () => {
    const sellTax = await cygn.sellTax();
    const buyTax = await cygn.buyTax();

    expect(sellTax.liquidity).to.equal(SELL_TAX.liquidity);
    expect(sellTax.team).to.equal(SELL_TAX.team);
    expect(sellTax.rewards).to.equal(SELL_TAX.rewards);

    expect(buyTax.liquidity).to.equal(BUY_TAX.liquidity);
    expect(buyTax.team).to.equal(BUY_TAX.team);
    expect(buyTax.rewards).to.equal(BUY_TAX.rewards);
  });

  it("should have the right default  info", async () => {
    const [owner, rewards, autoLP, team] = await ethers.getSigners();

    const factoryAddress = await cygn.uniFactory();
    const routerAddress = await cygn.uniRouter();
    const pairAddress = await cygn.uniPair();

    expect(factoryAddress).to.equal(await uniFactory.getAddress());
    expect(routerAddress).to.equal(await uniRouter.getAddress());
    expect(pairAddress).to.equal(pairAddress);

    const totalSupply = await cygn.totalSupply();

    expect(totalSupply).to.equal(INITIAL_SUPPLY);

    expect(await cygn.balanceOf(owner.address)).to.equal(INITIAL_SUPPLY);

    expect(await cygn.isExcludedFromFee(owner.address)).to.equal(true);
    expect(await cygn.isExcludedFromFee(await cygn.getAddress())).to.equal(
      true
    );

    expect(await cygn.isPair(pairAddress)).to.equal(true);
  });

  it("should not allow a bad tax", async () => {
    await expect(
      cygn.setSellTax(badTax.liquidity, badTax.team, badTax.rewards)
    ).to.be.revertedWith("CygnusNetwork: tax too high");

    await expect(
      cygn.setBuyTax(badTax.liquidity, badTax.team, badTax.rewards)
    ).to.be.revertedWith("CygnusNetwork: tax too high");
  });

  it("should allow owner only to change the tax", async () => {
    const [owner, rewards, autoLP, team] = await ethers.getSigners();

    await expect(
      cygn
        .connect(rewards)
        .setSellTax(VALID_TAX.liquidity, VALID_TAX.team, VALID_TAX.rewards)
    ).to.be.revertedWithCustomError(cygn, "OwnableUnauthorizedAccount");

    await expect(
      cygn
        .connect(rewards)
        .setBuyTax(VALID_TAX.liquidity, VALID_TAX.team, VALID_TAX.rewards)
    ).to.be.revertedWithCustomError(cygn, "OwnableUnauthorizedAccount");

    await cygn
      .connect(owner)
      .setSellTax(VALID_TAX.liquidity, VALID_TAX.team, VALID_TAX.rewards);

    await cygn
      .connect(owner)
      .setBuyTax(VALID_TAX.liquidity, VALID_TAX.team, VALID_TAX.rewards);

    const sellTax = await cygn.sellTax();
    const buyTax = await cygn.buyTax();

    expect(sellTax.liquidity).to.equal(VALID_TAX.liquidity);
    expect(sellTax.team).to.equal(VALID_TAX.team);
    expect(sellTax.rewards).to.equal(VALID_TAX.rewards);

    expect(buyTax.liquidity).to.equal(VALID_TAX.liquidity);
    expect(buyTax.team).to.equal(VALID_TAX.team);
    expect(buyTax.rewards).to.equal(VALID_TAX.rewards);

    await cygn
      .connect(owner)
      .setSellTax(SELL_TAX.liquidity, SELL_TAX.team, SELL_TAX.rewards);

    await cygn
      .connect(owner)
      .setBuyTax(BUY_TAX.liquidity, BUY_TAX.team, BUY_TAX.rewards);
  });

  it("should transfer without tax ", async () => {
    const [owner, rewards, autoLP, team, alice, bob, carl] =
      await ethers.getSigners();

    await cygn.transfer(alice.address, 1000n * 10n ** 18n);

    expect(await cygn.balanceOf(alice.address)).to.equal(1000n * 10n ** 18n);

    await cygn.connect(alice).transfer(bob.address, 100n * 10n ** 18n);

    expect(await cygn.balanceOf(bob.address)).to.equal(100n * 10n ** 18n);

    await cygn.connect(bob).transfer(carl.address, 10n * 10n ** 18n);

    expect(await cygn.balanceOf(carl.address)).to.equal(10n * 10n ** 18n);
  });

  it("should create LP ", async function () {
    const [owner, rewards, autoLP, team, alice, bob, carl] =
      await ethers.getSigners();

    // approve 10000 token to uniswap router

    await cygn.approve(await uniRouter.getAddress(), 100000n * 10n ** 18n);

    // owner creates lp
    await uniRouter
      .connect(owner)
      //@ts-ignore
      .addLiquidityETH(
        await cygn.getAddress(),
        100000n * 10n ** 18n,
        0,
        0,
        owner.address,
        1000000000000000000n,
        { value: 100n * 10n ** 18n }
      );

    // expect balance of pair to be 10000 token and 100 weth
    const pair = await uniFactory.getPair(cygn.getAddress(), weth.getAddress());

    const pairContract = await ethers.getContractAt(uniswapPair.abi, pair);

    const [token0, token1] = await pairContract.getReserves();

    if (Number(weth.address) < Number(cygn.getAddress())) {
      expect(token0).to.equal(100n * 10n ** 18n);
      expect(token1).to.equal(10000n * 10n ** 18n);
    } else {
      expect(token0).to.equal(100000n * 10n ** 18n);
      expect(token1).to.equal(100n * 10n ** 18n);
    }
  });

  it("should allow only owner to enable taxes", async () => {
    const [owner, rewards, autoLP, team, alice, bob, carl] =
      await ethers.getSigners();

    await expect(
      cygn.connect(alice).setTaxEnabled(true)
    ).to.be.revertedWithCustomError(cygn, "OwnableUnauthorizedAccount");

    await cygn.connect(owner).setTaxEnabled(true);

    expect(await cygn.taxEnabled()).to.equal(true);
  });

  it("allows owner to change team, autoLP, and rewards addresses", async () => {
    const [owner, rewards, autoLP, team, alice, bob, carl] =
      await ethers.getSigners();

    await expect(
      cygn.connect(alice).setTeamHolder(carl.address)
    ).to.be.revertedWithCustomError(cygn, "OwnableUnauthorizedAccount");

    await cygn.connect(owner).setTeamHolder(carl.address);

    expect(await cygn.teamHolder()).to.equal(carl.address);

    // fails for address 0
    await expect(
      cygn.connect(owner).setTeamHolder(ethers.ZeroAddress)
    ).to.be.revertedWith("CygnusNetwork: zero address");

    await expect(
      cygn.connect(alice).setLiquidityHolder(carl.address)
    ).to.be.revertedWithCustomError(cygn, "OwnableUnauthorizedAccount");

    await cygn.connect(owner).setLiquidityHolder(carl.address);

    expect(await cygn.liquidityHolder()).to.equal(carl.address);

    // fails for address 0
    await expect(
      cygn.connect(owner).setLiquidityHolder(ethers.ZeroAddress)
    ).to.be.revertedWith("CygnusNetwork: zero address");

    await cygn.connect(owner).setTeamHolder(team.address);
    await cygn.connect(owner).setLiquidityHolder(autoLP.address);
  });

  it("only owner can exclude users from tax", async () => {
    const [owner, rewards, autoLP, team, alice, bob, carl] =
      await ethers.getSigners();

    await expect(
      cygn.connect(alice).setExcludedFromFee(alice.address, true)
    ).to.be.revertedWithCustomError(cygn, "OwnableUnauthorizedAccount");

    await cygn.connect(owner).setExcludedFromFee(alice.address, true);

    expect(await cygn.isExcludedFromFee(alice.address)).to.equal(true);

    await cygn.connect(owner).setExcludedFromFee(alice.address, false);
  });

  it("only owner can add a new pair", async () => {
    const [owner, rewards, autoLP, team, alice, bob, carl, fakeLP] =
      await ethers.getSigners();

    await expect(
      cygn.connect(alice).setPair(fakeLP.address, true)
    ).to.be.revertedWithCustomError(cygn, "OwnableUnauthorizedAccount");

    await cygn.connect(owner).setPair(fakeLP.address, true);

    expect(await cygn.isPair(fakeLP.address)).to.equal(true);

    // fails to remove pair
    await expect(
      cygn.connect(alice).setPair(fakeLP.address, false)
    ).to.be.revertedWithCustomError(cygn, "OwnableUnauthorizedAccount");
  });

  it("fails to receive ETH", async function () {
    const [owner, rewards, autoLP, team, alice, bob, carl, fakeLP] =
      await ethers.getSigners();

    // expect sending eth from owner to contract address to fail
    await expect(
      owner.sendTransaction({
        to: cygn.getAddress(),
        value: ethers.parseEther("1.0"),
      })
    ).to.be.revertedWith("Invalid sender");
  });

  it("burns tokens", async function () {
    const [owner, rewards, autoLP, team, alice, bob, carl, fakeLP] =
      await ethers.getSigners();

    const initialSupply = await cygn.totalSupply();

    await cygn.connect(owner).burn(100n * 10n ** 18n);

    const newSupply = await cygn.totalSupply();

    expect(newSupply).to.equal(initialSupply - 100n * 10n ** 18n);
  });

  it("only owner can set miniBeforeLiquify", async function () {
    const [owner, rewards, autoLP, team, alice, bob, carl, fakeLP] =
      await ethers.getSigners();

    await expect(
      cygn.connect(alice).setMiniBeforeLiquify(100n * 10n ** 18n)
    ).to.be.revertedWithCustomError(cygn, "OwnableUnauthorizedAccount");

    await cygn.connect(owner).setMiniBeforeLiquify(100n * 10n ** 18n);

    expect(await cygn.miniBeforeLiquify()).to.equal(100n * 10n ** 18n);
  });

  it("should pay no tax on transfer", async function () {
    const [owner, rewards, autoLP, team, alice, bob, carl, fakeLP] =
      await ethers.getSigners();

    await expect(cygn.connect(owner).setTaxEnabled(true)).to.be.revertedWith(
      "CygnusNetwork: already set"
    );

    // burn all alice tokens
    await cygn.connect(alice).burn(await cygn.balanceOf(alice.address));
    // burn all bob tokens
    await cygn.connect(bob).burn(await cygn.balanceOf(bob.address));
    // burn all carl tokens
    await cygn.connect(carl).burn(await cygn.balanceOf(carl.address));

    await cygn.connect(owner).transfer(alice.address, 100n * 10n ** 18n);

    expect(await cygn.balanceOf(alice.address)).to.equal(100n * 10n ** 18n);

    await cygn.connect(alice).transfer(bob.address, 100n * 10n ** 18n);

    expect(await cygn.balanceOf(bob.address)).to.equal(100n * 10n ** 18n);

    await cygn.connect(bob).transfer(carl.address, 10n * 10n ** 18n);

    expect(await cygn.balanceOf(carl.address)).to.equal(10n * 10n ** 18n);
  });

  it("should pay buy tax on buy", async function () {
    const [owner, rewards, autoLP, team, alice, bob, carl, fakeLP] =
      await ethers.getSigners();

    // burn all alice, bob, and carl tokens
    await cygn.connect(alice).burn(await cygn.balanceOf(alice.address));
    await cygn.connect(bob).burn(await cygn.balanceOf(bob.address));
    await cygn.connect(carl).burn(await cygn.balanceOf(carl.address));

    const amountsOut = await uniRouter.getAmountsOut(1n * 10n ** 18n, [
      await weth.getAddress(),
      await cygn.getAddress(),
    ]);

    await uniRouter
      .connect(alice)
      //@ts-ignore
      .swapExactETHForTokensSupportingFeeOnTransferTokens(
        0,
        [await weth.getAddress(), await cygn.getAddress()],
        alice.address,
        999999999999999999n,
        { value: 1n * 10n ** 18n }
      );

    const expectedAmount =
      amountsOut[1] -
      (amountsOut[1] * (BUY_TAX.liquidity + BUY_TAX.team + BUY_TAX.rewards)) /
        TAX_DENOMINATOR;

    const balanceOfAlice = await cygn.balanceOf(alice.address);

    expect(balanceOfAlice).to.closeTo(expectedAmount, 1n);
  });

  it("should pay sell tax on sell", async function () {
    const [owner, rewards, autoLP, team, alice, bob1, carl, fakeLP, bob] =
      await ethers.getSigners();

    // burn all alice, bob, and carl tokens
    await cygn.connect(alice).burn(await cygn.balanceOf(alice.address));
    await cygn.connect(bob).burn(await cygn.balanceOf(bob.address));
    await cygn.connect(carl).burn(await cygn.balanceOf(carl.address));

    await cygn.connect(owner).transfer(bob.address, 100n * 10n ** 18n);

    const pairBalanceBefore = await cygn.balanceOf(pairAddress);

    const amountsOut2 = await uniRouter.getAmountsOut(100n * 10n ** 18n, [
      await cygn.getAddress(),
      await weth.getAddress(),
    ]);

    await cygn
      .connect(bob)
      .approve(await uniRouter.getAddress(), 100n * 10n ** 18n);

    await uniRouter
      .connect(bob)
      //@ts-ignore
      .swapExactTokensForETHSupportingFeeOnTransferTokens(
        100n * 10n ** 18n,
        0,
        [await cygn.getAddress(), await weth.getAddress()],
        bob.address,
        999999999999999999n
      );

    const expectedAmount2 =
      amountsOut2[0] -
      (amountsOut2[0] *
        (SELL_TAX.liquidity + SELL_TAX.team + SELL_TAX.rewards)) /
        TAX_DENOMINATOR;

    const lpBalanceAfter = await cygn.balanceOf(pairAddress);

    // expect bob to have no balance
    expect(await cygn.balanceOf(bob.address)).to.equal(0);

    expect(lpBalanceAfter - pairBalanceBefore).to.closeTo(expectedAmount2, 1n);
  });

  it("should still work if taxes are set to zero", async () => {
    const [owner, rewards, autoLP, team, alice, bob1, carl, fakeLP, bob] =
      await ethers.getSigners();

    await cygn.connect(owner).setSellTax(0, 0, 0);
    await cygn.connect(owner).setBuyTax(0, 0, 0);

    // burn all alice, bob, and carl tokens
    await cygn.connect(alice).burn(await cygn.balanceOf(alice.address));
    await cygn.connect(bob).burn(await cygn.balanceOf(bob.address));
    await cygn.connect(carl).burn(await cygn.balanceOf(carl.address));

    await cygn.connect(owner).transfer(bob.address, 100n * 10n ** 18n);
    await cygn.connect(owner).transfer(carl.address, 100n * 10n ** 18n);
    await cygn.connect(owner).transfer(alice.address, 100n * 10n ** 18n);

    // bob, alice and carl buy 1eth worth of cygn each
    const users = [bob, alice, carl];

    for (let i = 0; i < users.length; i++) {
      await uniRouter
        .connect(users[i])
        //@ts-ignore
        .swapExactETHForTokensSupportingFeeOnTransferTokens(
          0,
          [await weth.getAddress(), await cygn.getAddress()],
          bob.address,
          999999999999999999n,
          { value: 1n * 10n ** 18n }
        );
    }

    // bob, alice and carl sell 1eth worth of cygn each
    for (let i = 0; i < users.length; i++) {
      await cygn
        .connect(users[i])
        .approve(await uniRouter.getAddress(), 100n * 10n ** 18n);

      await uniRouter
        .connect(users[i])
        //@ts-ignore
        .swapExactTokensForETHSupportingFeeOnTransferTokens(
          100n * 10n ** 18n,
          0,
          [await cygn.getAddress(), await weth.getAddress()],
          bob.address,
          999999999999999999n
        );
    }

    // transfer between users
    for (let i = 0; i < users.length - 1; i++) {
      await cygn
        .connect(users[i])
        .transfer(users[i + 1].address, 1n * 10n ** 18n);
    }
  });

  it("should swap and liquify", async () => {
    const [owner, rewards, autoLP, team, alice, bob1, carl, fakeLP, bob] =
      await ethers.getSigners();

    // owner balance
    const ownerBalance = await cygn.balanceOf(owner.address);

    // set taxes back
    await cygn
      .connect(owner)
      .setSellTax(SELL_TAX.liquidity, SELL_TAX.team, SELL_TAX.rewards);
    await cygn
      .connect(owner)
      .setBuyTax(BUY_TAX.liquidity, BUY_TAX.team, BUY_TAX.rewards);

    // burn all alice, bob, and carl tokens
    await cygn.connect(alice).burn(await cygn.balanceOf(alice.address));
    await cygn.connect(bob).burn(await cygn.balanceOf(bob.address));
    await cygn.connect(carl).burn(await cygn.balanceOf(carl.address));

    await cygn.connect(owner).transfer(alice.address, 100n * 10n ** 18n);

    // set miniBeforeLiquify to 0
    await cygn.connect(owner).setMiniBeforeLiquify(0);

    const rewardsReserves = await cygn.rewardsReserves();

    // alice sells her 100 tokens
    await cygn
      .connect(alice)
      .approve(await uniRouter.getAddress(), 100n * 10n ** 18n);

    const liquidityReserves = await cygn.liquidityReserves();

    const lpPairBalanceBefore = await cygn.balanceOf(pairAddress);

    await uniRouter
      .connect(alice)
      //@ts-ignore
      .swapExactTokensForETHSupportingFeeOnTransferTokens(
        100n * 10n ** 18n,
        0,
        [await cygn.getAddress(), await weth.getAddress()],
        alice.address,
        999999999999999999n
      );

    const lpPairBalanceAfter = await cygn.balanceOf(pairAddress);

    const expectedOut = 100n * 10n ** 18n - (100n * 10n ** 18n * 20n) / 100n;

    expect(lpPairBalanceAfter - lpPairBalanceBefore).to.closeTo(
      expectedOut + liquidityReserves + rewardsReserves,
      3n * 10n ** 16n
    );
  });
});
