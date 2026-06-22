// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract Ownable {
    address private _owner;

    constructor () {
        _owner = msg.sender;
    }

    function owner() public view returns (address) {
        return _owner;
    }

    modifier onlyOwner() {
        require(_owner == msg.sender, "Ownable: caller is not the owner");
        _;
    }
    //转移所有权
    function transferOwnership(address newOwner) public onlyOwner {
        _owner = newOwner;
    }
}

contract Admin {
    address public admin;

    constructor () {
        admin = msg.sender;
    }

    modifier onlyAdmin() {
        require(admin == msg.sender, "admin: caller is not the admin");
        _;
    }
    //转移管理员权限
    function transferAdmin(address newAdmin) public onlyAdmin {
        admin = newAdmin;
    }
}