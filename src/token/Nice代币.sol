// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "../libraries/ERC20StandardToken.sol";
import "../libraries/Ownable.sol";
import "../interfaces/IPancake.sol";

interface INode {
    function processDividendToken(uint256 amount) external;
}

interface IStaking {
    function addRedeemAmount24h(uint256 a) external;
}

contract Nice is ERC20StandardToken, Ownable, Admin {

    mapping (address => bool) public isExcludedFromFees;
    address private constant operateAddress = 0x3F2B6889b2C32122835630903Bb76dfEa21e9CA7;
    address private constant communityFeeAddress = 0x1DdcAaDa302E6cB2886FF7d67D5C44960d7BA23C;
    address private constant communityProfitAddress = 0x0a4e4234FF7258673bA5C8B2a32Bc8c34Dc326CA;
    address private constant planningAddress = 0x67F14F28Bd45492C5Cb5434A7a81E29C910DE710;
    address private constant deadAddress = 0x000000000000000000000000000000000000dEaD;

    address public stakeContract;
    address public nodeContract;

    uint256 public coolingTime = 60;
    struct UserSwapInfo {
        uint256 lastBuyTime;
        uint256 usdtAmount;
    }
    mapping(address => UserSwapInfo) public userSwaps;
    address public immutable usdtPair;

    bool public canBuy;
    uint256 public poolAmount = 1000*10**22;
    bool public isAdd24;

    // Nice   Nice Token    18   700000000000000000000000000
    constructor(string memory symbol_, string memory name_, uint8 decimals_, uint256 totalSupply_) ERC20StandardToken(symbol_, name_, decimals_, totalSupply_) {
        address factory = 0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73;
        address usdt = 0x55d398326f99059fF775485246999027B3197955;
        usdtPair = pairFor(factory, usdt, address(this));
    }

    function pairFor(address factory, address tokenA, address tokenB) internal pure returns (address pair_) {
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        pair_ = address(uint160(uint(keccak256(abi.encodePacked(
                hex'ff',
                factory,
                keccak256(abi.encodePacked(token0, token1)),
                hex'00fb7f630766e6a796048ea87d01acd3068e8ff67d078148a3fa3f4a84f69bd5'
        )))));
    }

    function setContract(address s, address n) external onlyOwner {
        stakeContract = s;
        nodeContract = n;
    }

    function setCool(uint256 c) external onlyOwner {
        require(c <= 3600, 'c');
        coolingTime = c;
    }

    function setCanBuy(bool c, uint256 p) external onlyAdmin {
        canBuy = c;
        poolAmount = p;
    }

    function setA(bool a) external onlyAdmin {
        isAdd24 = a;
    }

    function setExcludeFee(address[] calldata addrs, bool b) external onlyAdmin {
        uint256 len = addrs.length;
        for (uint256 i; i < len; ++i) {
            isExcludedFromFees[addrs[i]] = b;
        }
    }

    function _transfer(address from, address to, uint256 amount) internal override {
        address pair = usdtPair;
        if(from != pair && to != pair) {
            super._transfer(from, to, amount);
            return;
        }
        
        if(isExcludedFromFees[from] || isExcludedFromFees[to]) {
            super._transfer(from, to, amount);
            return;
        }

        if(!canBuy) {
            _updateCanBuy(pair);
        }

        if(from == stakeContract || to == stakeContract) {
            super._transfer(from, to, amount);
            return;
        }

        _subSenderBalance(from, amount);
        if(from == pair) {
            require(canBuy, 'c');
            (uint reserveUSDT, uint reserveToken,) = IPancakePair(pair).getReserves();
            userSwaps[to].usdtAmount += getAmountIn(amount, reserveUSDT, reserveToken);
            userSwaps[to].lastBuyTime = block.timestamp;
            _addReceiverBalance(from, to, amount - _processSwap(from, amount));
        }else {
            require(block.timestamp >= userSwaps[from].lastBuyTime + coolingTime, 'cool');

            uint256 remainAmount = amount - _processSwap(from, amount);
            (uint reserveUSDT, uint reserveToken,) = IPancakePair(pair).getReserves();
            uint256 usdtAmount = getAmountOut(remainAmount, reserveToken, reserveUSDT);

            uint256 u = userSwaps[from].usdtAmount;
            uint256 profitTax;
            uint256 u24h;
            if(usdtAmount <= u) {
                userSwaps[from].usdtAmount = u - usdtAmount;
                u24h = usdtAmount;
            }else if(u > 0){
                uint256 userUSDT = (3*usdtAmount + u)/4;
                uint256 userToken = getAmountIn(userUSDT, reserveToken, reserveUSDT);
                profitTax = remainAmount - userToken;
                userSwaps[from].usdtAmount = 0;
                u24h = userUSDT;
            }else {
                profitTax = remainAmount/4;
                u24h = getAmountOut(remainAmount-profitTax, reserveToken, reserveUSDT);
            }
            if(isAdd24) {
                // 24h赎回量增加，降低赎回率
                IStaking(stakeContract).addRedeemAmount24h(u24h);
            }
            
            if(profitTax > 0) {
                _processProfitTax(from, profitTax);
            }
            _addReceiverBalance(from, to, remainAmount - profitTax);
        }
    }

    function _updateCanBuy(address pair) private {
        (uint reserveUSDT, ,) = IPancakePair(pair).getReserves();
        if(reserveUSDT >= poolAmount) {
            canBuy = true;
        }
    }

    function _processSwap(address from, uint256 amount) private returns(uint256) {
        uint256 oAmount = amount/100;
        _addReceiverBalance(from, operateAddress, oAmount);

        _addReceiverBalance(from, nodeContract, oAmount);
        //
        INode(nodeContract).processDividendToken(oAmount);

        uint256 cAmount = amount*3/200;
        _addReceiverBalance(from, communityFeeAddress, cAmount);
        return (2*oAmount + cAmount);
    }

    function _processProfitTax(address from, uint256 amount) private {
        uint256 dAmount = amount/5;
        _addReceiverBalance(from, deadAddress, dAmount);

        uint256 nodeAmount = amount*2/5;
        _addReceiverBalance(from, nodeContract, nodeAmount);
        INode(nodeContract).processDividendToken(nodeAmount);

        uint256 pAmount = amount/50;
        _addReceiverBalance(from, planningAddress, pAmount);

        _addReceiverBalance(from, communityProfitAddress, amount - dAmount - nodeAmount - pAmount);
    }

    function recycle(uint256 amount) external {
        address s = stakeContract;
        require(s == msg.sender, "r");
        super._transfer(usdtPair, s, amount);
        IPancakePair(usdtPair).sync();
    }

    function addUserBuy(address addr, uint256 amount) external {
        require(msg.sender == stakeContract, "r");
        userSwaps[addr].usdtAmount += amount;
    }

    // given an output amount of an asset and pair reserves, returns a required input amount of the other asset
    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut) internal pure returns (uint amountIn) {
        require(amountOut > 0, 'INSUFFICIENT_OUTPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'INSUFFICIENT_LIQUIDITY');
        uint numerator = reserveIn*amountOut*10000;
        uint denominator = (reserveOut-amountOut)*9975;
        amountIn = (numerator / denominator)+1;
    }

    // given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) internal pure returns (uint amountOut) {
        require(amountIn > 0, 'INSUFFICIENT_INPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'INSUFFICIENT_LIQUIDITY');
        uint amountInWithFee = amountIn*9975;
        uint numerator = amountInWithFee*reserveOut;
        uint denominator = reserveIn*10000 + amountInWithFee;
        amountOut = numerator / denominator;
    }
}