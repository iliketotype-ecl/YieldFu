// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "hardhat/console.sol";  // For logging purposes

/// @title YieldFuToken
/// @notice ERC20 token for the YieldFu protocol with minting, burning, permit functionality, and pausable transfers.
/// @dev This contract does not handle permissions itself. It is interacted with by protocol modules like MINTR or DEBASE.
contract YieldFuToken is ERC20, ERC20Burnable, ERC20Permit, Pausable {
    // =========  EVENTS ========= //
    event DebaseIndexUpdated(uint256 newDebaseIndex);

    // =========  STATE ========= //
    uint256 public debaseIndex = 1e18;  // Default value for 1:1 index

    // =========  ERRORS ========= //
    error YieldFuToken_InvalidAddress();
    error YieldFuToken_ZeroAmount();
    error YieldFuToken_NotAuthorized();

    /// @dev Constructor to set up initial values for the token
    /// @param name_ Token name
    /// @param symbol_ Token symbol
    /// @param initialSupply Initial token supply
    /// @param admin_ Initial admin address (usually the protocol's deployer or owner)
    constructor(
        string memory name_,
        string memory symbol_,
        uint256 initialSupply,
        address admin_
    ) ERC20(name_, symbol_) ERC20Permit(name_) {
        if (admin_ == address(0)) revert YieldFuToken_InvalidAddress();
        if (initialSupply == 0) revert YieldFuToken_ZeroAmount();

        _mint(admin_, initialSupply); // Mint the initial supply to the admin
    }

    // =========  TOKEN OPERATIONS ========= //

    /// @notice Mint new tokens to the specified address
    /// @dev This should only be callable by the MINTR module (or other authorized contract).
    /// @param to The address to mint the tokens to
    /// @param amount The number of tokens to mint
    function mint(address to, uint256 amount) external {
        console.log("YIELDFU: Mint called by:", msg.sender);
        _mint(to, amount);
    }

    /// @notice Burn tokens from a specific address
    /// @dev This should only be callable by the BURNR module (or other authorized contract).
    /// @param from The address to burn tokens from
    /// @param amount The number of tokens to burn
    function burnFrom(address from, uint256 amount) public override {
        console.log("YIELDFU: Burn called by:", msg.sender);
        super.burnFrom(from, amount);
    }

    /// @notice Updates the global debase index used to adjust balances
    /// @dev This function is called by the DEBASE module when debasing happens.
    /// @param newIndex The new value for the debase index.
    function updateDebaseIndex(uint256 newIndex) external  {
        console.log("YIELDFU: Updating debase index from", debaseIndex, "to", newIndex);
        debaseIndex = newIndex;
        emit DebaseIndexUpdated(newIndex);
    }

    /// @notice Returns the adjusted balance of an account considering the debase index
    /// @param account The address of the account whose balance is being queried.
    /// @return The balance adjusted by the debase index.
    function balanceOf(address account) public view override returns (uint256) {
        uint256 rawBalance = super.balanceOf(account);
        return (rawBalance * debaseIndex) / 1e18; // Apply the debase index
    }

    /// @notice Returns the adjusted total supply of the token considering the debase index
    /// @return The total supply adjusted by the debase index.
    function totalSupply() public view override returns (uint256) {
        uint256 rawSupply = super.totalSupply();
        return (rawSupply * debaseIndex) / 1e18; // Adjust for debase index
    }

    // =========  PAUSING ========= //

    /// @notice Pause token transfers
    /// @dev This should only be callable by an authorized module or protocol owner.
    function pause() external {
        console.log("YIELDFU: Pause called by:", msg.sender);
        _pause();
    }

    /// @notice Unpause token transfers
    /// @dev This should only be callable by an authorized module or protocol owner.
    function unpause() external {
        console.log("YIELDFU: Unpause called by:", msg.sender);
        _unpause();
    }

    // Override transfer functions to include pausable functionality
    function transfer(address to, uint256 amount) public override whenNotPaused returns (bool) {
        return super.transfer(to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) public override whenNotPaused returns (bool) {
        return super.transferFrom(from, to, amount);
    }
}
