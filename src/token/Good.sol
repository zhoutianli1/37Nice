// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "../libraries/ERC20StandardToken.sol";
import "../libraries/Ownable.sol";

contract Good is ERC20StandardToken, Ownable, Admin {

    address public stakeContract;

    // Good  Good  18   1000000000000000000
    constructor(string memory symbol_, string memory name_, uint8 decimals_, uint256 totalSupply_) ERC20StandardToken(symbol_, name_, decimals_, totalSupply_) {

    }

    function setContract(address s) external onlyAdmin {
        stakeContract = s;
    }

    function mint(address addr, uint256 amount) external {
        require(msg.sender == stakeContract, 's');
        _mint(addr, amount);
    }
    
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    function burnFrom(address account, uint256 amount) external {
        _spendAllowance(account, msg.sender, amount);
        _burn(account, amount);
    }
}