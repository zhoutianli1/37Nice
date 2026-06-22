// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;
//0xD153dadCE8dfb5B2FCe7e69481C96c8809535b1d
import "../libraries/Ownable.sol";

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from,address to,uint256 amount) external returns (bool);
}

interface IStaking {
    function isUserExists(address addr) external view returns (bool);
    function getLastIdx() external view returns(uint256);
    function getSumRewardRateLastIdx(uint256 rewardIdx) external view returns(uint256, uint256);
    function sendToken(address addr, uint256 amount) external;
    function addGenNode(address addr) external;
}

contract GenesisNode is Ownable, Admin {
    IERC20 private constant c_erc20 = IERC20(0xE4a67909FAc4949e31fBc22c87ddCD5ca2b6F33D);
    IERC20 private constant c_usdt = IERC20(0x55d398326f99059fF775485246999027B3197955);
    
    IStaking private constant c_stake = IStaking(0x37c24C01dEa3c1d4385eAda6239E3D5958a8892c);
    address private constant usdtReceiver = 0xF90D8EA6fcCdFc8566E39E6267DcA0Af0533e81C;
    uint256 private constant nodeValue = 10**21;
    uint256 public minCount = 7;

    struct User {
        uint256 perDividend;
        uint256 withdrawnDividend;
        uint256 rewardIdx;
        uint256 withdrawnStaticReward;
    }
    mapping(address => User) public users;
    uint256 public nodeNum;
    uint256 public perDividend = 1;
    uint256 public totalDividend;
    //项目方发放节点奖励，增加每个节点的分红金额
    function processDividendToken(uint256 amount) external {
        if(msg.sender == address(c_erc20) && amount > 0) {
            perDividend += amount/nodeNum;//当 nodeNum == 0 时会除零失败或回退
            totalDividend += amount;
        }
    }
    //用户购买节点，必须是质押过的用户
    function buyNode() external {        
        c_usdt.transferFrom(msg.sender, usdtReceiver, nodeValue);
        _addNode(msg.sender, perDividend, c_stake.getLastIdx());
        _limitNodeNum(1);
    }

    function setInterval(uint256 c) external onlyAdmin {
        require(c >= 1 && c <= 30, 'c');
        minCount = c;
    }
    //用于项目方批量添加节点，必须是质押过的用户
    function addNode(address[] calldata addrs) external onlyAdmin {
        uint256 len = addrs.length;
        uint256 p = perDividend;
        uint256 lastIdx = c_stake.getLastIdx();

        for (uint256 i = 0; i < len; i++) {
            _addNode(addrs[i], p, lastIdx);
        }
        _limitNodeNum(len);
    }

    function _addNode(address a, uint256 p, uint256 lastIdx) private {
        require(c_stake.isUserExists(a), 's');
        require(users[a].perDividend == 0, 'e');
        users[a].perDividend = p;
        users[a].rewardIdx = lastIdx;
        c_stake.addGenNode(a);
    }

    function _limitNodeNum(uint256 a) private {
        uint256 num = nodeNum + a;
        require(num <= 5000, 'n');
        nodeNum = num;
    }

    function removeNode(address[] calldata addrs) external onlyAdmin {
        uint256 len = addrs.length;
        for (uint256 i = 0; i < len; i++) {
            address a = addrs[i];
            require(users[a].perDividend > 0, 'e');
            users[a].perDividend = 0;
        }
        nodeNum -= len;
        require(nodeNum > 0, 'n');
    }
    //从节点合约 提取Nice收益
    function getDividend() external {
        User storage s = users[msg.sender];
        uint256 sp = s.perDividend;
        require(sp > 0, 'n1');

        uint256 p = perDividend;
        sp = p - sp;
        require(sp > 0, 'n2');

        s.perDividend = p;
        c_erc20.transfer(msg.sender, sp);
        s.withdrawnDividend += sp;
    }

    function getStaticReward() external {
        User storage s = users[msg.sender];
        require(s.perDividend > 0, 'e');
        (uint256 lastIdx, uint256 r) = getStaticRewardInfo(s.rewardIdx, s.withdrawnStaticReward);
        require(r > 0, 'r');
        require(lastIdx >= s.rewardIdx + minCount, 'm');
        c_stake.sendToken(msg.sender, r);
        s.rewardIdx = lastIdx;
        s.withdrawnStaticReward += r;
    }

    function getStaticRewardInfo(uint256 rewardIdx, uint256 w) public view returns(uint256, uint256) {
        (uint256 sumRate, uint256 lastIdx) = c_stake.getSumRewardRateLastIdx(rewardIdx);
        uint256 r = nodeValue*sumRate/10000;
        if(r + w > nodeValue) {
            r = nodeValue - w;
        }
        return (lastIdx, r);
    }

    function userInfo(address addr) external view returns (User memory o, uint256 d, uint256 r, uint256 lastIdx, uint256 m) {
        o = users[addr];
        if(o.perDividend > 0) {
            d = perDividend - o.perDividend;
            (lastIdx, r) = getStaticRewardInfo(o.rewardIdx, o.withdrawnStaticReward);
        }
        m = minCount;
    }

    function getDirectNode(address[] calldata addrs) external view returns(uint256[] memory pds) {
        uint256 len = addrs.length;
        pds = new uint256[](len);
        for (uint256 i; i < len; ++i) {
            pds[i] = users[addrs[i]].perDividend;
        }
    }
}