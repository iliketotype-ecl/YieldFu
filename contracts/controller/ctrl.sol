// Controller (ctrl) Contract
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../base/DEBASE.sol";
import "../base/STAKE.sol";
import "../base/BOND.sol";

contract ctrl is AccessControl, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    bytes32 public constant POLICY_ROLE = keccak256("POLICY_ROLE");

    DEBASE public immutable debaseToken;
    STAKE public immutable stakingContract;
    BOND public immutable bondingContract;

    event Minted(address indexed to, uint256 amount);
    event Burned(address indexed from, uint256 amount);
    event Debased(uint256 debasedAmount);
    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event RewardClaimed(address indexed user, uint256 reward);
    event BondCreated(address indexed user, uint256 deposit, bool isPartnerToken);
    event BondRedeemed(address indexed user, uint256 payout);

    constructor(
        address _debaseToken,
        address _stakingContract,
        address _bondingContract
    ) {
        require(_debaseToken != address(0), "Invalid DEBASE token address");
        require(_stakingContract != address(0), "Invalid staking contract address");
        require(_bondingContract != address(0), "Invalid bonding contract address");

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(POLICY_ROLE, msg.sender);
        
        debaseToken = DEBASE(_debaseToken);
        stakingContract = STAKE(_stakingContract);
        bondingContract = BOND(_bondingContract);
    }

    // Token functions
    function mint(address to, uint256 amount) external onlyRole(POLICY_ROLE) whenNotPaused nonReentrant {
        require(to != address(0), "Invalid address");
        require(amount > 0, "Amount must be greater than zero");

        debaseToken.mint(to, amount);
        emit Minted(to, amount);
    }

    function burn(address from, uint256 amount) external onlyRole(POLICY_ROLE) whenNotPaused nonReentrant {
        require(from != address(0), "Invalid address");
        require(amount > 0, "Amount must be greater than zero");

        debaseToken.burn(from, amount);
        emit Burned(from, amount);
    }

    function debase() external onlyRole(POLICY_ROLE) whenNotPaused nonReentrant {
        uint256 debasedAmount = debaseToken.rebase();
        emit Debased(debasedAmount);
    }

    // Staking functions
    function stake(address user, uint256 amount) external whenNotPaused nonReentrant {
        require(user != address(0), "Invalid address");
        require(amount > 0, "Amount must be greater than zero");

        IERC20 stakingToken = IERC20(stakingContract.stakingToken());
        stakingToken.safeTransferFrom(user, address(stakingContract), amount);
        stakingContract.stake(user, amount);
        emit Staked(user, amount);
    }

    function unstake(address user, uint256 amount) external whenNotPaused nonReentrant {
        require(user != address(0), "Invalid address");
        require(amount > 0, "Amount must be greater than zero");

        stakingContract.unstake(user, amount);
        IERC20 stakingToken = IERC20(stakingContract.stakingToken());
        stakingToken.safeTransfer(user, amount);
        emit Unstaked(user, amount);
    }

    function claimReward(address user) external whenNotPaused nonReentrant {
        uint256 reward = stakingContract.claimReward(user);
        require(reward > 0, "No rewards to claim");

        IERC20 rewardToken = IERC20(stakingContract.rewardToken());
        rewardToken.safeTransfer(user, reward);
        emit RewardClaimed(user, reward);
    }

    // Bonding functions
    function createBond(address user, uint256 deposit, bool isPartnerToken) external whenNotPaused nonReentrant {
        require(user != address(0), "Invalid address");
        require(deposit > 0, "Deposit must be greater than zero");

        uint256 payout = bondingContract.createBond(user, deposit, isPartnerToken);
        IERC20 depositToken = isPartnerToken ? IERC20(bondingContract.partnerToken()) : IERC20(bondingContract.debaseToken());
        depositToken.safeTransferFrom(user, address(this), deposit);
        emit BondCreated(user, deposit, isPartnerToken);
    }
    

    function redeemBond(address user) external whenNotPaused nonReentrant {
        uint256 payout = bondingContract.redeemBond(user);
        require(payout > 0, "No bond to redeem");

        require(debaseToken.transfer(user, payout), "Payout transfer failed");
        emit BondRedeemed(user, payout);
    }

    // Admin functions
    function setStakingAPY(uint256 newBaseAPY, uint256 newBoostAPY) external onlyRole(POLICY_ROLE) {
        stakingContract.setAPY(newBaseAPY, newBoostAPY);
    }

    function activateStakingBoost(uint256 duration) external onlyRole(POLICY_ROLE) {
        stakingContract.activateBoost(duration);
    }

       function setBondingDiscount(bool isPartnerToken, uint256 newDiscount) external onlyRole(POLICY_ROLE) {
        bondingContract.setDiscount(isPartnerToken, newDiscount);
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    // Safety measure
    function recoverERC20(address tokenAddress, uint256 tokenAmount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(tokenAddress != address(0), "Invalid token address");
        require(tokenAmount > 0, "Amount must be greater than zero");

        if (tokenAddress == address(debaseToken)) {
            require(debaseToken.transfer(msg.sender, tokenAmount), "DEBASE transfer failed");
        } else {
            IERC20(tokenAddress).safeTransfer(msg.sender, tokenAmount);
        }
    }
}