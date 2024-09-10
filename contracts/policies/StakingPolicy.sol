// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.24;

import "../Kernel.sol";
import "../modules/STAKE.sol";

contract StakingPolicy is Policy {
    STAKE public staking;

    constructor(Kernel kernel_) Policy(kernel_) {
        staking = STAKE(getModuleAddress(toKeycode("STAKE")));
    }

    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](1);
        dependencies[0] = toKeycode("STAKE");
    }

    function requestPermissions() external view override returns (Permissions[] memory requests) {
        requests = new Permissions[](4);
        requests[0] = Permissions(toKeycode("STAKE"), staking.stake.selector);
        requests[1] = Permissions(toKeycode("STAKE"), staking.unstake.selector);
        requests[2] = Permissions(toKeycode("STAKE"), staking.getReward.selector);
        requests[3] = Permissions(toKeycode("STAKE"), staking.boostAPY.selector);
    }

    function stake(uint256 amount) external {
        staking.stake(amount);
    }

    function unstake(uint256 amount) external {
        staking.unstake(amount);
    }

    function getReward() external {
        staking.getReward();
    }

    function boostAPY(uint256 duration) external {
        staking.boostAPY(duration);
    }
}