// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity >=0.8.23;

import {Distributor} from "../src/Distributor.sol";
import {WarpCore} from "../src/WarpCore.sol";

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {IUniswapV2Factory} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {IUniFactory} from "../src/WarpCore.sol";

contract Deployer is Script {
    Distributor distributor;
    WarpCore warpCore;

    function run() public {
        vm.startBroadcast(
            uint(0) //Privare key of the deployer
        );
        warpCore = new WarpCore(
            msg.sender, //ownerAddress,
            payable(address(5555555555)), //teamHolderAddress,
            payable(address(5555555555)), //liquidityHolderAddress,
            IUniswapV2Router02(address(5555555555)), //uniswapV2RouterAddress,
            IUniFactory(address(5555555555)) //uniswapV2FactoryAddress
        );

        console2.log("WarpCore deployed at: ", address(warpCore));

        distributor = new Distributor(
            address(5555555555) //owner
        );

        console2.log("distributor deployed at: ", address(warpCore));

        vm.stopBroadcast();
    }
}
