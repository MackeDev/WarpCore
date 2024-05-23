// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.23;

import {HolderRewards} from "./RewardsDistributor.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Distributor is HolderRewards {
    constructor(address owner) Ownable(owner) {}
}
