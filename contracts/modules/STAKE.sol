// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.24;

import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../Kernel.sol";
import "../YieldFu.sol";

contract STAKE is Module, Pausable, ReentrancyGuard {
    // =========  EVENTS ========= //
    event Stake(address indexed user, uint256 amount);
    event Unstake(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event APYChanged(uint256 newBaseAPY, uint256 newBoostedAPY);
    event APYBoosted(uint256 boostEndTime);
    event CooldownSet(uint256 newCooldown);
    event EarlyUnstakeSlashSet(uint256 newSlashRate);
    event MaxStakeCapSet(uint256 newMaxStakeCap);

    // ========= ERRORS ========= //
    error STAKE_ZeroAmount();
    error STAKE_InsufficientBalance();
    error STAKE_CooldownNotMet();
    error STAKE_MaxStakeCapExceeded();
    error STAKE_InvalidAPY();
    error STAKE_InvalidCooldown();
    error STAKE_InvalidSlashRate();

    // =========  STATE ========= //
    YieldFuToken public token;
    uint256 public baseAPY;
    uint256 public boostedAPY;
    uint256 public boostEndTime;
    uint256 public cooldownPeriod;
    uint256 public earlyUnstakeSlashRate; // In basis points (e.g., 500 = 5%)
    uint256 public maxStakeCap;
    uint256 public totalStaked;

    struct StakeInfo {
        uint256 amount;
        uint256 lastUpdateTime;
        uint256 lastStakeTime;
    }

    mapping(address => StakeInfo) public stakes;

    constructor(
        Kernel kernel_,
        YieldFuToken token_,
        uint256 initialBaseAPY_,
        uint256 initialBoostedAPY_,
        uint256 initialCooldown_,
        uint256 initialSlashRate_,
        uint256 initialMaxStakeCap_
    ) Module(kernel_) {
        token = token_;
        baseAPY = initialBaseAPY_;
        boostedAPY = initialBoostedAPY_;
        cooldownPeriod = initialCooldown_;
        earlyUnstakeSlashRate = initialSlashRate_;
        maxStakeCap = initialMaxStakeCap_;
    }

    function KEYCODE() public pure override returns (Keycode) {
        return toKeycode("STAKE");
    }

    function VERSION() external pure override returns (uint8 major, uint8 minor) {
        return (1, 1); // v1.1
    }

    function INIT() external override onlyKernel {
        // Initialization logic, if any
    }

    function stake(uint256 amount) external nonReentrant whenNotPaused permissioned {
        if (amount == 0) revert STAKE_ZeroAmount();
        if (totalStaked + amount > maxStakeCap) revert STAKE_MaxStakeCapExceeded();

        updateReward(msg.sender);
        stakes[msg.sender].amount += amount;
        stakes[msg.sender].lastStakeTime = block.timestamp;
        totalStaked += amount;

        token.transferFrom(msg.sender, address(this), amount);
        emit Stake(msg.sender, amount);
    }

    function unstake(uint256 amount) external nonReentrant whenNotPaused permissioned {
        StakeInfo storage userStake = stakes[msg.sender];
        if (amount == 0) revert STAKE_ZeroAmount();
        if (userStake.amount < amount) revert STAKE_InsufficientBalance();

        updateReward(msg.sender);
        
        uint256 slashAmount = 0;
        if (block.timestamp < userStake.lastStakeTime + cooldownPeriod) {
            slashAmount = (amount * earlyUnstakeSlashRate) / 10000;
        }

        userStake.amount -= amount;
        totalStaked -= amount;

        uint256 transferAmount = amount - slashAmount;
        token.transfer(msg.sender, transferAmount);
        if (slashAmount > 0) {
            token.burn(slashAmount);
        }

        emit Unstake(msg.sender, amount);
    }

    function getReward() external nonReentrant whenNotPaused permissioned {
        updateReward(msg.sender);
        uint256 reward = stakes[msg.sender].lastUpdateTime;
        if (reward > 0) {
            stakes[msg.sender].lastUpdateTime = 0;
            token.transfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    function updateReward(address account) internal {
        StakeInfo storage userStake = stakes[account];
        uint256 timeElapsed = block.timestamp - userStake.lastUpdateTime;
        uint256 reward = (userStake.amount * getCurrentAPY() * timeElapsed) / (365 days * 10000);
        userStake.lastUpdateTime = block.timestamp;
        userStake.lastUpdateTime += reward;
    }

    function getCurrentAPY() public view returns (uint256) {
        return block.timestamp < boostEndTime ? boostedAPY : baseAPY;
    }

    function setAPY(uint256 newBaseAPY, uint256 newBoostedAPY) external permissioned {
        if (newBaseAPY > 10000 || newBoostedAPY > 10000) revert STAKE_InvalidAPY(); // Max 100% APY
        baseAPY = newBaseAPY;
        boostedAPY = newBoostedAPY;
        emit APYChanged(newBaseAPY, newBoostedAPY);
    }

    function boostAPY(uint256 duration) external permissioned {
        boostEndTime = block.timestamp + duration;
        emit APYBoosted(boostEndTime);
    }

    function setCooldownPeriod(uint256 newCooldown) external permissioned {
        if (newCooldown > 30 days) revert STAKE_InvalidCooldown();
        cooldownPeriod = newCooldown;
        emit CooldownSet(newCooldown);
    }

    function setEarlyUnstakeSlashRate(uint256 newSlashRate) external permissioned {
        if (newSlashRate > 5000) revert STAKE_InvalidSlashRate(); // Max 50% slash
        earlyUnstakeSlashRate = newSlashRate;
        emit EarlyUnstakeSlashSet(newSlashRate);
    }

    function setMaxStakeCap(uint256 newMaxStakeCap) external permissioned {
        maxStakeCap = newMaxStakeCap;
        emit MaxStakeCapSet(newMaxStakeCap);
    }

    // View functions
    function getStakeInfo(address user) external view returns (
        uint256 stakedAmount,
        uint256 pendingRewards,
        uint256 lastStakeTime,
        bool inCooldown
    ) {
        StakeInfo memory userStake = stakes[user];
        uint256 timeElapsed = block.timestamp - userStake.lastUpdateTime;
        uint256 reward = (userStake.amount * getCurrentAPY() * timeElapsed) / (365 days * 10000);
        
        return (
            userStake.amount,
            userStake.lastUpdateTime + reward,
            userStake.lastStakeTime,
            block.timestamp < userStake.lastStakeTime + cooldownPeriod
        );
    }

    function pause() external permissioned {
        _pause();
    }

    function unpause() external permissioned {
        _unpause();
    }
}