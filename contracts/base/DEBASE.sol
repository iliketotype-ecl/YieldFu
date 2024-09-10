// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

contract DEBASE is ERC20, AccessControl, Pausable {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    uint256 public constant DAILY_DEVALUATION_RATE = 970000000000000000; // 97% (3% devaluation) in 18 decimal precision
    uint256 public constant DEVALUATION_PERIOD = 1 days;

    mapping(address => uint256) private _lastUpdateTime;

    constructor(string memory name, string memory symbol, uint256 initialSupply) ERC20(name, symbol) {
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(MINTER_ROLE, _msgSender());
        _mint(_msgSender(), initialSupply);
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual override {
        super._beforeTokenTransfer(from, to, amount);
        
        if (from != address(0)) {
            _updateBalance(from);
        }
        if (to != address(0)) {
            _updateBalance(to);
        }
    }

    function _updateBalance(address account) private {
        uint256 oldBalance = super.balanceOf(account);
        uint256 timeElapsed = block.timestamp - _lastUpdateTime[account];
        uint256 periods = timeElapsed / DEVALUATION_PERIOD;

        if (periods > 0) {
            uint256 newBalance = oldBalance;
            for (uint256 i = 0; i < periods; i++) {
                newBalance = (newBalance * DAILY_DEVALUATION_RATE) / 1e18;
            }
            _lastUpdateTime[account] = block.timestamp;
            
            if (newBalance < oldBalance) {
                _burn(account, oldBalance - newBalance);
            }
        }
    }

    function balanceOf(address account) public view virtual override returns (uint256) {
        uint256 rawBalance = super.balanceOf(account);
        uint256 timeElapsed = block.timestamp - _lastUpdateTime[account];
        uint256 periods = timeElapsed / DEVALUATION_PERIOD;

        if (periods > 0) {
            for (uint256 i = 0; i < periods; i++) {
                rawBalance = (rawBalance * DAILY_DEVALUATION_RATE) / 1e18;
            }
        }

        return rawBalance;
    }

    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) whenNotPaused {
        _updateBalance(to);
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyRole(MINTER_ROLE) whenNotPaused {
        _updateBalance(from);
        _burn(from, amount);
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }
}