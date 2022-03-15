// SPDX-License-Identifier: MIT
pragma solidity 0.8.12;
interface IPriceFeed {
    function getData(address tokenAddress) external view returns (uint256);
}