// SPDX-License-Identifier: MIT
pragma solidity 0.8.12;
interface IVault {
  function balanceOf(address) external view returns(uint256);
  function getPricePerFullShare() external view returns(uint256);
  function token() external view returns(address);
  function totalSupply() external view returns(uint256);
}