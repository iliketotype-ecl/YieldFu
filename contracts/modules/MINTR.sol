// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../Kernel.sol";
import "../YieldFu.sol"; // Import YieldFu token contract

/// @notice MINTR handles minting and burning of YieldFu tokens.
contract MINTR is Module {
    // =========  EVENTS ========= //

    event Mint(address indexed policy_, address indexed to_, uint256 amount_);
    event Burn(address indexed policy_, address indexed from_, uint256 amount_);
    event IncreaseMintApproval(address indexed policy_, uint256 newAmount_);
    event DecreaseMintApproval(address indexed policy_, uint256 newAmount_);

    // ========= ERRORS ========= //

    error MINTR_NotApproved();
    error MINTR_ZeroAmount();
    error MINTR_NotActive();

    // =========  STATE ========= //

    YieldFuToken public yieldFu;  // Reference to the YieldFu token
    bool public active;     // Status of the module (active/inactive)

    /// @notice Mapping of who is approved for minting.
    mapping(address => uint256) public mintApproval;

    address public constant BLACK_HOLE = 0x000000000000000000000000000000000000dEaD;

    constructor(Kernel kernel_, YieldFuToken yieldFu_) Module(kernel_) {
        yieldFu = yieldFu_;
        active = true;
    }

    modifier onlyWhileActive() {
        if (!active) revert MINTR_NotActive();
        _;
    }

    /// @notice Mint YieldFu tokens to an address.
    function mint(address to_, uint256 amount_) external onlyWhileActive permissioned {
        if (amount_ == 0) revert MINTR_ZeroAmount();
        if (mintApproval[msg.sender] < amount_) revert MINTR_NotApproved();

        mintApproval[msg.sender] -= amount_;
        yieldFu.mint(to_, amount_); // Mint YieldFu tokens to the address
        emit Mint(msg.sender, to_, amount_);
    }


    /// @notice Burn YieldFu tokens by sending them to a black hole address.
    function burn(address from_, uint256 amount_) external onlyWhileActive permissioned {
        if (amount_ == 0) revert MINTR_ZeroAmount();

        yieldFu.transferFrom(from_, BLACK_HOLE, amount_); // Send tokens to burn address
        emit Burn(msg.sender, from_, amount_);
    }

    /// @notice Increase mint approval for a specific policy.
    function increaseMintApproval(address policy_, uint256 amount_) external onlyKernel {
        mintApproval[policy_] += amount_;
        emit IncreaseMintApproval(policy_, amount_);
    }

    /// @notice Decrease mint approval for a specific policy.
    function decreaseMintApproval(address policy_, uint256 amount_) external onlyKernel {
        mintApproval[policy_] -= amount_;
        emit DecreaseMintApproval(policy_, amount_);
    }

    /// @notice Emergency shutdown of minting and burning.
    function deactivate() external onlyKernel {
        active = false;
    }

    /// @notice Re-activate minting and burning after shutdown.
    function activate() external onlyKernel {
        active = true;
    }

    function KEYCODE() public pure override returns (Keycode) {
        return toKeycode("MINTR");  // Return the module keycode
    }
}
