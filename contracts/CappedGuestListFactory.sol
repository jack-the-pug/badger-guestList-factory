// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.12;

import "@openzeppelin/contracts/proxy/Clones.sol";

import "./CappedGuestList.sol";

/// @title The CappedGuestListFactory allows users to create CappedGuestList very cheaply.
contract CappedGuestListFactory {
  using Clones for address;

  /// @notice The instance to which all proxies will point.
  CappedGuestList public cappedGuestListInstance;

  /// @notice Contract constructor.
  constructor() {
    cappedGuestListInstance = new CappedGuestList();
  }

  /**
   * @notice Creates a clone of the CappedGuestList.
   * @param _slot Random number used to deterministically deploy the clone
   * @param _owner owner of guestList
   * @param _vault the Vault the guestList is for,
   * @param _priceCalculator the PriceCalculator for guestList,
   * @return The newly created delegation
   */
  function createCappedGuestList(uint256 _slot, address _owner, address _vault, address _priceCalculator, uint256 _userDepositCap, uint256 _totalDepositCap) public returns (address) {
    bytes32 _salt = _computeSalt(_vault, _slot);
    CappedGuestList _guestList = CappedGuestList(address(cappedGuestListInstance).cloneDeterministic(_salt));
    _guestList.initialize(_owner, _vault, _priceCalculator, _userDepositCap, _totalDepositCap);
    return address(_guestList);
  }

  /**
   * @notice Computes the address of a clone, also known as minimal proxy contract.
   * @param _salt Random number used to compute the address
   * @return Address at which the clone will be deployed
   */
  function _computeAddress(bytes32 _salt) internal view returns (address) {
    return address(cappedGuestListInstance).predictDeterministicAddress(_salt, address(this));
  }

  /**
   * @notice Computes salt used to deterministically deploy a clone.
   * @param _vault Address of the vault
   * @param _slot Slot of the delegation
   * @return Salt used to deterministically deploy a clone.
   */
  function _computeSalt(address _vault, uint256 _slot) internal pure returns (bytes32) {
    return keccak256(abi.encodePacked(_vault, _slot));
  }
}
