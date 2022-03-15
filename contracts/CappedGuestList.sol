// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/MerkleProofUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import './interfaces/IVault.sol';
import './interfaces/IPriceCalculator.sol';


/**
 * @notice A basic guest list contract.
 * @dev For a Vyper implementation of this contract containing additional
 * functionality, see https://github.com/banteg/guest-list/blob/master/contracts/GuestList.vy
 * The owner can invite arbitrary guests
 * A guest can be added permissionlessly with proof of inclusion in current merkle set
 * The owner can change the merkle root at any time
 * Merkle-based permission that has been claimed cannot be revoked permissionlessly.
 * Any guests can be revoked by the owner at-will
 * The TVL cap is based on the number of want tokens in the underlying vaults.
 * This can only be made more permissive over time. If decreased, existing TVL is maintained and no deposits are possible until the TVL has gone below the threshold
 * A variant of the yearn AffiliateToken that supports guest list control of deposits
 * A guest list that gates access by merkle root and a TVL cap
 * @notice authorized function to ignore merkle proof for testing, inspiration from yearn's approach to testing guestlist https://github.com/yearn/yearn-devdocs/blob/4664fdef7d10f3a767fa651975059c44cf1cdb37/docs/developers/v2/smart-contracts/test/TestGuestList.md
 */
contract CappedGuestList is OwnableUpgradeable {
    using SafeMathUpgradeable for uint256;

    address public wantToken;
    address public vault;
    address public priceCalculator;

    bytes32 public guestRoot;
    uint256 public userDepositCap;
    uint256 public totalDepositCap;

    mapping(address => bool) public guests;

    event ProveInvitation(address indexed account, bytes32 indexed guestRoot);
    event SetGuestRoot(bytes32 indexed guestRoot);
    event SetUserDepositCap(uint256 cap);
    event SetTotalDepositCap(uint256 cap);

    /**
     * @notice Create the guest list
     */
    function initialize(address _owner, address _vault, address _priceCalculator, uint256 _userDepositCap, uint256 _totalDepositCap) public initializer {
        __Ownable_init();
        transferOwnership(_owner);
        vault = _vault;
        wantToken = IVault(vault).token();
        priceCalculator = _priceCalculator;
        userDepositCap = _userDepositCap;
        totalDepositCap = _totalDepositCap;
    }

    /**
     * @notice Invite guests or kick them from the party.
     * @param _guests The guests to add or update.
     * @param _invited A flag for each guest at the matching index, inviting or
     * uninviting the guest.
     */
    function setGuests(address[] calldata _guests, bool[] calldata _invited) external onlyOwner {
        _setGuests(_guests, _invited);
    }

    function remainingTotalDepositAllowed() public view returns (uint256) {
        uint256 totalSupply = IVault(vault).totalSupply();
        uint256 pricePerShare = IVault(vault).getPricePerFullShare();
        uint256 totalTokenPriceInUSD = IPriceCalculator(priceCalculator).tokenPriceInUSD(wantToken, totalSupply * pricePerShare);

        return totalDepositCap.sub(totalTokenPriceInUSD);
    }

    function remainingUserDepositAllowed(address user) public view returns (uint256) {
        uint256 userBalance = IVault(vault).balanceOf(user);
        uint256 pricePerShare = IVault(vault).getPricePerFullShare();
        uint256 totalTokenPriceInUSD = IPriceCalculator(priceCalculator).tokenPriceInUSD(wantToken, userBalance * pricePerShare);
        return userDepositCap.sub(totalTokenPriceInUSD);
    }

    /**
     * @notice Permissionly prove an address is included in the current merkle root, thereby granting access
     * @notice Note that the list is designed to ONLY EXPAND in future instances
     * @notice The admin does retain the ability to ban individual addresses
     */
    function proveInvitation(address account, bytes32[] calldata merkleProof) public {
        // Verify Merkle Proof
        require(_verifyInvitationProof(account, merkleProof), "!merkleProof");

        address[] memory accounts = new address[](1);
        bool[] memory invited = new bool[](1);

        accounts[0] = account;
        invited[0] = true;

        _setGuests(accounts, invited);

        emit ProveInvitation(account, guestRoot);
    }

    /**
     * @notice Set the merkle root to verify invitation proofs against.
     * @notice Note that accounts not included in the root will still be invited if their inviation was previously approved.
     * @notice Setting to 0 removes proof verification versus the root, opening access
     */
    function setGuestRoot(bytes32 guestRoot_) external onlyOwner {
        guestRoot = guestRoot_;

        emit SetGuestRoot(guestRoot);
    }

    function setUserDepositCap(uint256 cap_) external onlyOwner {
        userDepositCap = cap_;

        emit SetUserDepositCap(userDepositCap);
    }

    function setTotalDepositCap(uint256 cap_) external onlyOwner {
        totalDepositCap = cap_;

        emit SetTotalDepositCap(totalDepositCap);
    }

    /**
     * @notice Check if a guest with a bag of a certain size is allowed into
     * the party.
     * @param _guest The guest's address to check.
     */
    function authorized(
        address _guest,
        uint256 _amount,
        bytes32[] calldata _merkleProof
    ) external view returns (bool) {
        // Yes: If the user is on the list, and under the cap
        // Yes: If the user is not on the list, and is under the cap
        // No: If the user is not on the list, or is over the cap
        bool invited = guests[_guest];

        // If there is no guest root, all users are invited
        if (!invited && guestRoot == bytes32(0)) {
            invited = true;
        }

        // If the user is not already invited and there is an active guestList, require verification of merkle proof to grant temporary invitation (does not set storage variable)
        if (!invited && guestRoot != bytes32(0)) {
            // Will revert on invalid proof
            invited = _verifyInvitationProof(_guest, _merkleProof);
        }

        // If the user was previously invited, or proved invitiation via list, verify if the amount to deposit keeps them under the cap
        if (invited && remainingUserDepositAllowed(_guest) >= _amount && remainingTotalDepositAllowed() >= _amount) {
            return true;
        } else {
            return false;
        }
    }

    function _setGuests(address[] memory _guests, bool[] memory _invited) internal {
        require(_guests.length == _invited.length, "!length");
        for (uint256 i = 0; i < _guests.length; i++) {
            if (_guests[i] == address(0)) {
                continue;
            }
            guests[_guests[i]] = _invited[i];
        }
    }

    function _verifyInvitationProof(address account, bytes32[] calldata merkleProof) internal view returns (bool) {
        bytes32 node = keccak256(abi.encodePacked(account));
        return MerkleProofUpgradeable.verify(merkleProof, guestRoot, node);
    }
}