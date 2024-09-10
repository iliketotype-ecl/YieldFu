// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.24;

import "./DEBASE.sol";
import "../Kernel.sol";

contract STAKE is Module {
    // =========  EVENTS ========= //
    event Stake(address indexed user, uint256 amount);
    event Unstake(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event APYBoosted(uint256 newAPY, uint256 duration);

    // ========= ERRORS ========= //
    error STAKE_ZeroAmount();
    error STAKE_InsufficientBalance();

    // =========  STATE ========= //
    DEBASE public token;
    uint256 public constant BASE_APY = 1333; // 1333% APY
    uint256 public constant BOOSTED_APY = 8888; // 8888% APY
    uint256 public currentAPY;
    uint256 public boostEndTime;

    mapping(address => uint256) public stakedBalance;
    mapping(address => uint256) public lastUpdateTime;

    constructor(Kernel kernel_, address token_) Module(kernel_) {
        token = DEBASE(token_);
        currentAPY = BASE_APY;
    }

    function KEYCODE() public pure override returns (Keycode) {
        return toKeycode("STAKE");
    }

    function VERSION() external pure override returns (uint8 major, uint8 minor) {
        return (1, 0); // v1.0
    }

    function INIT() external override onlyKernel {
        // Initialization logic, if any
    }

    function stake(uint256 amount) external permissioned {
        if (amount == 0) revert STAKE_ZeroAmount();
        if (token.balanceOf(msg.sender) < amount) revert STAKE_InsufficientBalance();

        updateReward(msg.sender);
        stakedBalance[msg.sender] += amount;
        token.transferFrom(msg.sender, address(this), amount);

        emit Stake(msg.sender, amount);
    }

    function unstake(uint256 amount) external permissioned {
        if (amount == 0) revert STAKE_ZeroAmount();
        if (stakedBalance[msg.sender] < amount) revert STAKE_InsufficientBalance();

        updateReward(msg.sender);
        stakedBalance[msg.sender] -= amount;
        token.transfer(msg.sender, amount);

        emit Unstake(msg.sender, amount);
    }

    function getReward() external permissioned {
        updateReward(msg.sender);
        uint256 reward = calculateReward(msg.sender);
        if (reward > 0) {
            lastUpdateTime[msg.sender] = block.timestamp;
            token.transfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    function updateReward(address account) internal {
        lastUpdateTime[account] = block.timestamp;
    }

    function calculateReward(address account) public view returns (uint256) {
        uint256 timeElapsed = block.timestamp - lastUpdateTime[account];
        return (stakedBalance[account] * currentAPY * timeElapsed) / (365 days * 100);
    }

    function boostAPY(uint256 duration) external permissioned {
        currentAPY = BOOSTED_APY;
        boostEndTime = block.timestamp + duration;
        emit APYBoosted(BOOSTED_APY, duration);
    }

    function checkAndUpdateAPY() internal {
        if (block.timestamp > boostEndTime && currentAPY == BOOSTED_APY) {
            currentAPY = BASE_APY;
        }
    }
}