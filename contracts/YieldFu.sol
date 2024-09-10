// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./Kernel.sol"; // Assuming you have a Kernel.sol for permissions and modules
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

/// @title YieldFuToken
/// @notice ERC20 token for the YieldFu protocol with minting, burning, and permit functionality.
contract YieldFuToken is ERC20, ERC20Burnable, ERC20Permit, AccessControl {
    Kernel public kernel; // Reference to the Kernel contract (your permission system)
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE"); // Role identifier for minters
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE"); // Role identifier for burners

    /// @dev Constructor to set up initial values for the token
    /// @param _kernel Reference to the Kernel contract for permission management
    /// @param name_ Token name
    /// @param symbol_ Token symbol
    /// @param initialSupply Initial token supply
    /// @param minter_ Initial minter address
    constructor(
        Kernel _kernel,
        string memory name_,
        string memory symbol_,
        uint256 initialSupply,
        address minter_
    ) ERC20(name_, symbol_) ERC20Permit(name_) {
        kernel = _kernel;

        // Set up roles using AccessControl
        _grantRole(MINTER_ROLE, minter_);
        _grantRole(BURNER_ROLE, minter_);

        // Mint the initial supply to the minter
        _mint(minter_, initialSupply);
    }

    /// @notice Mint new tokens to the specified address
    /// @dev Restricted to accounts with the MINTER_ROLE
    /// @param to The address to mint the tokens to
    /// @param amount The number of tokens to mint
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    /// @notice Burn tokens from a specific address
    /// @dev Restricted to accounts with the BURNER_ROLE
    /// @param from The address to burn tokens from
    /// @param amount The number of tokens to burn
    function burnFrom(address from, uint256 amount) public override onlyRole(BURNER_ROLE) {
        super.burnFrom(from, amount);
    }

    /// @notice Update the minter role to a new address
    /// @dev Restricted to Kernel governance (executor role)
    /// @param newMinter The address of the new minter
    function setMinter(address newMinter) external {
        require(msg.sender == kernel.executor(), "YieldFuToken: Only Kernel executor can set minter");
        _grantRole(MINTER_ROLE, newMinter);
    }

    /// @notice Update the burner role to a new address
    /// @dev Restricted to Kernel governance (executor role)
    /// @param newBurner The address of the new burner
    function setBurner(address newBurner) external {
        require(msg.sender == kernel.executor(), "YieldFuToken: Only Kernel executor can set burner");
        _grantRole(BURNER_ROLE, newBurner);
    }
}

