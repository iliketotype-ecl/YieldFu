// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../Kernel.sol";
import "../YieldFu.sol";

/// @notice DEBASE applies periodic debasement to the YieldFu token.
contract DEBASE is Module {
    // =========  EVENTS ========= //
    event Debase(uint256 amount);
    
    // ========= ERRORS ========= //
    error DEBASE_TooSoon();

    // =========  STATE ========= //

    YieldFuToken public yieldFu;
    uint256 public constant DEBASE_RATE = 30; // 3% debasement rate (30/1000)
    uint256 public constant DEBASE_INTERVAL = 1 days; // Time interval for debasement
    uint256 public lastDebaseTime;

    constructor(Kernel kernel_, YieldFuToken yieldFu_) Module(kernel_) {
        yieldFu = yieldFu_;
        lastDebaseTime = block.timestamp;
    }

    modifier onlyAfterInterval() {
        if (block.timestamp < lastDebaseTime + DEBASE_INTERVAL) revert DEBASE_TooSoon();
        _;
    }

    /// @notice Debase the YieldFu token.
    function debase() external permissioned onlyAfterInterval {
        uint256 totalSupply = yieldFu.totalSupply();
        uint256 debaseAmount = (totalSupply * DEBASE_RATE) / 1000;
        yieldFu.burn(debaseAmount); // Burn the debase amount from the supply

        lastDebaseTime = block.timestamp;
        emit Debase(debaseAmount);
    }

    function KEYCODE() public pure override returns (Keycode) {
        return toKeycode("DBASE");  // Return the module keycode
    }
}
