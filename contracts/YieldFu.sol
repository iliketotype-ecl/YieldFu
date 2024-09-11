// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol"; // Use AccessControlEnumerable
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol"; // Updated import to OpenZeppelin's security Pausable

/// @title YieldFuToken
/// @notice ERC20 token for the YieldFu protocol with minting, burning, permit functionality, and pausable transfers.
contract YieldFuToken is ERC20, ERC20Burnable, ERC20Permit, AccessControlEnumerable, Pausable {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    // =========  EVENTS ========= //
    event MinterSet(address indexed newMinter);
    event BurnerSet(address indexed newBurner);
    event PauserSet(address indexed newPauser);

    // =========  ERRORS ========= //
    error YieldFuToken_InvalidAddress();
    error YieldFuToken_ZeroAmount();

    /// @dev Constructor to set up initial values for the token
    /// @param name_ Token name
    /// @param symbol_ Token symbol
    /// @param initialSupply Initial token supply
    /// @param admin_ Initial admin address
    constructor(
        string memory name_,
        string memory symbol_,
        uint256 initialSupply,
        address admin_
    ) ERC20(name_, symbol_) ERC20Permit(name_) {
        if (admin_ == address(0)) revert YieldFuToken_InvalidAddress();
        if (initialSupply == 0) revert YieldFuToken_ZeroAmount();

        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(MINTER_ROLE, admin_);
        _grantRole(BURNER_ROLE, admin_);
        _grantRole(PAUSER_ROLE, admin_);

        _mint(admin_, initialSupply);
    }

    /// @notice Mint new tokens to the specified address
    /// @dev Restricted to accounts with the MINTER_ROLE
    /// @param to The address to mint the tokens to
    /// @param amount The number of tokens to mint
    function mint(address to, uint256 amount) public onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }


    /// @notice Burn tokens from a specific address
    /// @dev Restricted to accounts with the BURNER_ROLE
    /// @param from The address to burn tokens from
    /// @param amount The number of tokens to burn
    function burnFrom(address from, uint256 amount) public override onlyRole(BURNER_ROLE) {
        if (from == address(0)) revert YieldFuToken_InvalidAddress();
        if (amount == 0) revert YieldFuToken_ZeroAmount();
        super.burnFrom(from, amount);
    }

    /// @notice Update the minter role to a new address
    /// @param newMinter The address of the new minter
    function setMinter(address newMinter) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newMinter == address(0)) revert YieldFuToken_InvalidAddress();
        address currentMinter = _getRoleMember(MINTER_ROLE);
        if (currentMinter != address(0)) {
            _revokeRole(MINTER_ROLE, currentMinter);
        }
        _grantRole(MINTER_ROLE, newMinter);
        emit MinterSet(newMinter);
    }

    /// @notice Update the burner role to a new address
    /// @param newBurner The address of the new burner
    function setBurner(address newBurner) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newBurner == address(0)) revert YieldFuToken_InvalidAddress();
        address currentBurner = _getRoleMember(BURNER_ROLE);
        if (currentBurner != address(0)) {
            _revokeRole(BURNER_ROLE, currentBurner);
        }
        _grantRole(BURNER_ROLE, newBurner);
        emit BurnerSet(newBurner);
    }

    /// @notice Update the pauser role to a new address
    /// @param newPauser The address of the new pauser
    function setPauser(address newPauser) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newPauser == address(0)) revert YieldFuToken_InvalidAddress();
        address currentPauser = _getRoleMember(PAUSER_ROLE);
        if (currentPauser != address(0)) {
            _revokeRole(PAUSER_ROLE, currentPauser);
        }
        _grantRole(PAUSER_ROLE, newPauser);
        emit PauserSet(newPauser);
    }

    /// @notice Pause token transfers
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /// @notice Unpause token transfers
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    // Override transfer functions to include pausable functionality
    function transfer(address to, uint256 amount) public override whenNotPaused returns (bool) {
        return super.transfer(to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) public override whenNotPaused returns (bool) {
        return super.transferFrom(from, to, amount);
    }

    // Internal function to get the first member of a role
    function _getRoleMember(bytes32 role) internal view returns (address) {
        uint256 memberCount = getRoleMemberCount(role);
        if (memberCount > 0) {
            return getRoleMember(role, 0);
        }
        return address(0);
    }
}
