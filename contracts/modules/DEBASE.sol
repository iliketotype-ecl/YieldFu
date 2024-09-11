// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.24;

import "@openzeppelin/contracts/utils/Pausable.sol";
import "../Kernel.sol";
import "../YieldFu.sol";
import "hardhat/console.sol"; // Keep this for logging 

/// @notice DEBASE applies periodic debasement to the YieldFu token with adjustable rates.
contract DEBASE is Module, Pausable {
    // =========  EVENTS ========= //
    event Debase(uint256 amount);
    event DebaseRateChanged(uint256 newRate);
    event DebaseIntervalChanged(uint256 newInterval);
    event MinDebaseThresholdChanged(uint256 newThreshold);
    event DebasePaused(address indexed by);
    event DebaseUnpaused(address indexed by);
    
    // ========= ERRORS ========= //
    error DEBASE_TooSoon();
    error DEBASE_InvalidRate();
    error DEBASE_InvalidInterval();
    error DEBASE_InvalidThreshold();
    error DEBASE_BelowMinThreshold();

// =========  STATE ========= //
    YieldFuToken public yieldFu;
    uint256 public debaseRate; // Debasement rate in basis points (1 bp = 0.01%)
    uint256 public debaseInterval; // Time interval for debasement
    uint256 public lastDebaseTime;
    uint256 public minDebaseThreshold; // Minimum token supply threshold for debasement

    constructor(
        Kernel kernel_,
        YieldFuToken yieldFu_,
        uint256 initialDebaseRate_,
        uint256 initialDebaseInterval_,
        uint256 initialMinDebaseThreshold_
    ) Module(kernel_) {
        yieldFu = yieldFu_;
        debaseRate = initialDebaseRate_;
        debaseInterval = initialDebaseInterval_;
        minDebaseThreshold = initialMinDebaseThreshold_;
        lastDebaseTime = block.timestamp;
    }

    modifier onlyAfterInterval() {
        console.log("DEBASE: Checking debase interval");
        console.log("DEBASE: Current time", block.timestamp);
        console.log("DEBASE: Last debase time", lastDebaseTime);
        console.log("DEBASE: Interval", debaseInterval);
        if (block.timestamp < lastDebaseTime + debaseInterval) {
            console.log("DEBASE: Too soon to debase");
            revert DEBASE_TooSoon();
        }
        _;
    }

    /// @notice Debase the YieldFu token.
    function debase() external permissioned onlyAfterInterval whenNotPaused {
        console.log("DEBASE: Debase function called");
        uint256 totalSupply = yieldFu.totalSupply();
        console.log("DEBASE: Total supply", totalSupply);
        console.log("DEBASE: Min debase threshold", minDebaseThreshold);
        if (totalSupply < minDebaseThreshold) {
            console.log("DEBASE: Supply below threshold");
            revert DEBASE_BelowMinThreshold();
        }
        
        uint256 debaseAmount = (totalSupply * debaseRate) / 10000; // Convert basis points to percentage
        console.log("DEBASE: Debase amount", debaseAmount);
        yieldFu.burn(debaseAmount); // Burn the debase amount from the supply

        lastDebaseTime = block.timestamp;
        emit Debase(debaseAmount);
        console.log("DEBASE: Debase successful");
    }


    /// @notice Change the debasement rate.
    function changeDebaseRate(uint256 newRate) external permissioned {
        if (newRate > 1000) revert DEBASE_InvalidRate(); // Max 10% debasement
        debaseRate = newRate;
        emit DebaseRateChanged(newRate);
    }

    /// @notice Change the debasement interval.
    function changeDebaseInterval(uint256 newInterval) external permissioned {
        if (newInterval < 1 hours || newInterval > 30 days) revert DEBASE_InvalidInterval();
        debaseInterval = newInterval;
        emit DebaseIntervalChanged(newInterval);
    }

    /// @notice Change the minimum debasement threshold.
    function changeMinDebaseThreshold(uint256 newThreshold) external permissioned {
        if (newThreshold == 0) revert DEBASE_InvalidThreshold();
        minDebaseThreshold = newThreshold;
        emit MinDebaseThresholdChanged(newThreshold);
    }

    /// @notice Pause the debasement function.
    function pauseDebase() external permissioned {
        _pause();
        emit DebasePaused(msg.sender);
    }

    /// @notice Unpause the debasement function.
    function unpauseDebase() external permissioned {
        _unpause();
        emit DebaseUnpaused(msg.sender);
    }

    // View functions
    function getDebaseInfo() external view returns (
        uint256 currentRate,
        uint256 currentInterval,
        uint256 lastDebase,
        uint256 nextDebase,
        bool isPaused
    ) {
        return (
            debaseRate,
            debaseInterval,
            lastDebaseTime,
            lastDebaseTime + debaseInterval,
            paused()
        );
    }

    function KEYCODE() public pure override returns (Keycode) {
        return toKeycode("DBASE");
    }

    function VERSION() external pure override returns (uint8 major, uint8 minor) {
        return (1, 1); // Updated to v1.1
    }
}