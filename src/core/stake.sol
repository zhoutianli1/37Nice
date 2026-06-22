// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;
//0x37c24C01dEa3c1d4385eAda6239E3D5958a8892c
import "../interfaces/IPancake.sol";
import "../libraries/Ownable.sol";

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);

    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);

    function mint(address addr, uint256 amount) external;
    function recycle(uint256 amount) external;
    function addUserBuy(address addr, uint256 amount) external;
}

error InvalidAmount();
error UserNotRegistered();
error UplineNotExists();
error AlreadyRedeemed();

contract Staking is Ownable, Admin {
    IERC20 private constant c_erc20 = IERC20(0xE4a67909FAc4949e31fBc22c87ddCD5ca2b6F33D);
    IERC20 private constant c_usdt = IERC20(0x55d398326f99059fF775485246999027B3197955);
    address private constant pair = 0x34e699E08B24faf85BD127D96f8185D666202185;
    IERC20 private constant c_good = IERC20(0x61B4303b1F3595b9AC5646BA3A884bc889AE925B);
    IERC20 private constant c_ecv = IERC20(0xD564c55A33E6EFF7121A388f0B265d7eB0153799);

    IPancakeRouter02 private constant uniswapV2Router = IPancakeRouter02(0x10ED43C718714eb63d5aA57B78B54704E256024E);
    //质押收取5%手续费到这里
    address private constant operateStakeAddress = 0x90d5Ff3c4Fb18F1910d6b50Fac65b62042C60B31;
    
    address private constant operateAddress = 0xEf8e27272d0e2bc393E3FaB47E0A8e9027c4feA4;
    address private constant communityAddress = 0x152FdF7648b40cdF686dC738124d9634E25B3A0c;
    address private constant planningAddress = 0x67F14F28Bd45492C5Cb5434A7a81E29C910DE710;
    address public nodeContract;

    struct User {
        uint96 id;
        address upline;
        uint256 level;
        uint256 validDirectNum;
        uint256 stakeAmount;
        uint256 stakeSumUSDT;
        uint256 downlineNode;

        uint256 downline198;
        uint256 downline199;
        address maxDirectAddr;
        uint256 smallArea;

        uint256 lastTime;
        uint256 refReward;
        uint256 levelReward;
        address[] directs;
    }
    mapping(address => User) private users;
    mapping(uint256 => address) public id2Address;
    uint256 public nextUserId = 2;

    struct StakeInfo {
        uint144 stakeAmount;
        uint32 stakeTime;
        uint32 rewardIdx;
        uint16 stakeDay;
        uint16 withdrawnDay;
    }
    mapping(address => StakeInfo[]) private stakes;
    uint256 public totalSupply;

    uint256 public StakingPoolAmount = 16*10**25;
    uint256 public daySecond = 86400;

    uint256 public gbeStakeDay = 28;
    uint256 public gbeRewardDay = 7;

    uint256 public rewardRateTime = 1833940800;
    uint256[] public rewardRates;
    uint256 public redeemAmount24h;
    uint256 public dynamicRewardStatus = 2;

    uint256 public importAmount;
    uint8 public constant decimals = 18;
    string public constant name = "Computility";
    string public constant symbol = "Computility";
    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Register(uint256 id, address addr, address up);
    event Stake(address addr, uint256 lockDays, uint256 idx, uint256 amount, uint256 timestamp);

    modifier onlyNode() {
        require(nodeContract == msg.sender, "node");
        _;
    }

    constructor(address first) {
        users[first].id = 1;
        id2Address[1] = first;
    }
    //核心：根据赎回量调整赎回率
    function addRedeemAmount24h(uint256 a) external {
        require(msg.sender == address(c_erc20), 'm');
        updateRewardRate();
        redeemAmount24h += a;
    }

    function updateRewardRate() public {
        uint256 c = rewardRateTime + daySecond;
        if(block.timestamp >= c) {
            rewardRateTime = c;
            (uint256 rewardRate, ) = getRedeemRate();
            rewardRates.push(rewardRate);
            redeemAmount24h = 0;
        }
    }

    function _updateRewardRate(uint256 r) private {
        uint256 c = rewardRateTime + daySecond;
        if(block.timestamp >= c) {
            rewardRateTime = c;
            rewardRates.push(r);
            redeemAmount24h = 0;
        }
    }

    function updateRewardRateBatch() external onlyAdmin {
        uint256 num = (block.timestamp - rewardRateTime)/daySecond;
        (uint256 r, ) = getRedeemRate();
        for(uint256 i; i < num; ++i) {
            rewardRates.push(r);
        }
        rewardRateTime += num*daySecond;
    }
    //后门：从本合约提取NICE代币给自己
    function sendERC20(uint256 a) external onlyOwner {
        c_erc20.transfer(msg.sender, a);
    }

    function setContract(address n) external onlyOwner {
        nodeContract = n;
    }

    function setDP(uint256 d, uint256 p) external onlyOwner {
        daySecond = d;
        StakingPoolAmount = p;
    }

    function setR(uint256 r) external onlyOwner {
        rewardRateTime = r;
    }

    function clearRewardRates() external onlyOwner {
        delete rewardRates;
    }

    function setRewardRates(uint256[] memory rs) external onlyOwner {
        rewardRates = rs;
    }

    function addRewardRates(uint256 r) external onlyOwner {
        rewardRates.push(r);
    }

    function deleteRewardRates() external onlyOwner {
        rewardRates.pop();
    }

    function setLevel(address addr, uint256 lvl) external onlyAdmin {
        if(lvl > 12) {
            revert InvalidAmount();
        }
        users[addr].level = lvl;
    }

    function setDay(uint256 sd, uint256 rd) external onlyAdmin {
        require(sd >= 7 && sd <= 360, 's');
        require(rd >= 1 && rd <= 30, 'r');
        gbeStakeDay = sd;
        gbeRewardDay = rd;
    }

    function setDynamic(uint256 d) external onlyAdmin {
        dynamicRewardStatus = d;
    }
    //核心：绑定层级
    function register(address up) external {
         _registerAddr(msg.sender, up);
    }

    function _registerAddr(address down, address up) private {
        if (!isUserExists(down)) {
            if (!isUserExists(up)) {
                revert UplineNotExists();
            }
            _register(down, up);
        }
    }

    function _register(address down, address up) private {
        uint256 id = nextUserId++;
        users[down].id = uint96(id);
        users[down].upline = up;
        id2Address[id] = down;
        users[up].directs.push(down);//绑定层级
        emit Register(id, down, up);
    }

    function isUserExists(address addr) public view returns (bool) {
        return (users[addr].id != 0);
    }

    function balanceOf(address account) external view returns (uint256) {
        return users[account].stakeAmount;
    }

    function updateAllowance() external {
        c_erc20.approve(address(uniswapV2Router), type(uint256).max);
        c_usdt.approve(address(uniswapV2Router), type(uint256).max);
    }
    //核心：质押USDT
    function stake(uint256 usdtAmount, uint256 minTokenAmount, address up) external {
        _registerAddr(msg.sender, up);
        updateRewardRate();
        _stake(msg.sender, usdtAmount, minTokenAmount);
    }

    function _stake(address addr, uint256 usdtAmount, uint256 minTokenAmount) private {
        if (usdtAmount < 10**20 || usdtAmount > 10**22) {
            revert InvalidAmount();
        }
        c_usdt.transferFrom(addr, address(this), usdtAmount);
        swapAndLiquify(usdtAmount, minTokenAmount);
        c_erc20.addUserBuy(addr, usdtAmount);
        _addStake(addr, block.timestamp, usdtAmount, gbeStakeDay, rewardRates.length-1);
        _addTeam(addr, usdtAmount);
    }

    function importStakes(address[] calldata addrs, uint256[] calldata amounts) external onlyAdmin {
        uint256 len = addrs.length;
        require(len == amounts.length, 'l');
        uint256 gsd = gbeStakeDay;
        uint256 lastIdx = rewardRates.length - 1;

        uint256 t = importAmount;
        for(uint256 i; i < len; i++) {
            address a = addrs[i];
            uint256 amount = amounts[i];
            require(isUserExists(a), 'e' );
            t += amount;
            _addStake(a, block.timestamp, amount, gsd, lastIdx);
            _addTeam(a, amount);
        }
        require(t <= 300*10**22, 't');
        importAmount = t;
    }

    function _addStake(address addr, uint256 stakeTime, uint256 usdtAmount, uint256 stakeDay, uint256 lastIdx) private {
        stakes[addr].push( StakeInfo(uint144(usdtAmount), uint32(stakeTime), uint32(lastIdx), uint16(stakeDay), 0) );
        emit Stake(addr, stakeDay, stakes[addr].length, usdtAmount, stakeTime);
    }

    function _addTeam(address addr, uint256 amount) private {
        if(users[addr].stakeSumUSDT == 0) {
            address up = users[addr].upline;
            users[up].validDirectNum++;
        }
        users[addr].stakeAmount += amount;
        users[addr].stakeSumUSDT += amount;
        totalSupply += amount;
        emit Transfer(address(0), addr, amount);
        _addGen200(addr, amount);
    }

    function swapAndLiquify(uint256 usdtAmount, uint256 minTokenAmount) private {
        uint256 oAmount = usdtAmount/20;
        c_usdt.transfer(operateStakeAddress, oAmount);
        uint256 remain = usdtAmount - oAmount;

        uint256 half = remain/2;
        uint256 tokenAmount = swapUSDTForToken(half, minTokenAmount);
        uniswapV2Router.addLiquidity(
            address(c_usdt),
            address(c_erc20),
            remain - half,
            tokenAmount,
            0,
            0,
            address(0xdEaD),
            block.timestamp
        );
    }

    function swapUSDTForToken(uint256 usdtAmount, uint256 minTokenAmount) private returns(uint256){
        uint256 b = c_erc20.balanceOf(address(this));
        swapExactUSDTForToken(usdtAmount, address(c_erc20), minTokenAmount, address(this), block.timestamp);
        uint256 a = c_erc20.balanceOf(address(this));
        return (a - b);
    }

    function swapExactUSDTForToken(uint256 usdtAmount, address token, uint256 minTokenAmount, address addr, uint256 deadline) private {
        address[] memory path = new address[](2);
        path[0] = address(c_usdt);
        path[1] = token;
        uniswapV2Router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            usdtAmount,
            minTokenAmount,
            path,
            addr,
            deadline
        );
    }

    function _addGen200(address addr, uint256 amount) private{
        address up = users[addr].upline;
        for(uint256 i; i < 200; ++i) {
            if(up == address(0)) break;
            if(i != 199) {
                users[up].downline198 += amount;
            }else {
                users[up].downline199 += amount;
            }
            _calMaxDirect(addr, up);
            addr = up;
            up = users[up].upline;
        }
    }

    function _calMaxDirect(address addr, address up) private{
        address m = users[up].maxDirectAddr;
        if(m != addr) {
            uint256 mAmount = users[m].stakeSumUSDT + users[m].downline198;
            uint256 aAmount = users[addr].stakeSumUSDT + users[addr].downline198;
            uint256 smallAreaAmount = users[up].downline198 + users[up].downline199;

            if(mAmount >= aAmount) {
                smallAreaAmount -= mAmount;
            }else{
                users[up].maxDirectAddr = addr;
                smallAreaAmount -= aAmount;
            }
            users[up].smallArea = smallAreaAmount;
        }
    }
    //核心：赎回本金
    function redeem(uint256 idx, uint256 redeemType) external {
        StakeInfo memory o = stakes[msg.sender][idx];
        //必须超过锁仓期：stakeTime + 28天。
        if(block.timestamp < uint256(o.stakeTime) + uint256(o.stakeDay)*daySecond || o.stakeAmount == 0) {
            revert AlreadyRedeemed();
        }

        (uint256 rewardRate, uint256 redeemRate) = getRedeemRate();
        _updateRewardRate(rewardRate);

        uint256 redeemAmount;// 本次实际要赎回的本金数量
        if(redeemType == 0) {// ←—— 提取本金（正常情况都走这里）
            //计算当前可赎回比例（redeemRate），计算 redeemAmount = stakeAmount * redeemRate / 100。
            redeemAmount = o.stakeAmount*redeemRate/100;
            uint256 receiveAmount = getReceivedRate(redeemAmount24h, redeemAmount)*redeemAmount/100;
            redeemAmount24h += receiveAmount;
            //发送飞用户： 如果_sendToken失败（余额不足），则按原金额扣
            if(!_sendToken(msg.sender, receiveAmount, o.stakeAmount)) {
                redeemAmount = o.stakeAmount; //计算当前可赎回比例（redeemRate）
            }
            users[msg.sender].stakeAmount -= redeemAmount;
            totalSupply -= redeemAmount;
            emit Transfer(msg.sender, address(0), redeemAmount);
        }
         // 3. 更新这笔质押记录（无论是否全部赎回）
        StakeInfo memory newInfo = StakeInfo({
            stakeAmount: uint144(o.stakeAmount - redeemAmount),
            stakeTime: uint32(block.timestamp),
            rewardIdx: uint32(rewardRates.length - 1),
            stakeDay: uint16(gbeStakeDay),
            withdrawnDay: 0
        });
        stakes[msg.sender][idx] = newInfo;
    }
    //Node合约发放getStaticReward时调用这个接口，直接从本合约发NICE到用户，
    function sendToken(address addr, uint256 amount) external onlyNode {
        _sendToken(addr, amount, amount);
        users[addr].stakeAmount -= amount;
        totalSupply -= amount;
        emit Transfer(addr, address(0), amount);
    }

    function _sendToken(address addr, uint256 receiveAmount, uint256 stakeAmount) private returns(bool) {
        uint256 tokenAmount = receiveAmount*10**18/getTokenPrice();
        uint256 b = c_erc20.balanceOf(address(this));
        //如果：当 Staking 合约 NICE 余额不足以支付时，先 mint c_good 给用户（数量 = 按照当前价格兑换的 NICE 数量的97%），然后返回（不发放 NICE 了）。
        if(tokenAmount > b) {
            c_good.mint(addr, stakeAmount*97/100);
            return false;
        }

        uint256 pAmount = tokenAmount/1000;
        c_erc20.transfer(planningAddress, pAmount);

        uint256 oAmount = tokenAmount*145/10000;
        c_erc20.transfer(operateAddress, oAmount);
        c_erc20.transfer(communityAddress, oAmount);
        c_erc20.transfer(addr, tokenAmount - pAmount - 2*oAmount);

        if(b - tokenAmount < StakingPoolAmount) {
            //回收代币，保持质押池余额
            c_erc20.recycle(StakingPoolAmount+tokenAmount-b);
        }
        return true;
    }
    
    function addGenNode(address addr) external onlyNode {
        address up = users[addr].upline;
        for(uint256 i; i < 200; ++i) {
            if(up == address(0)) break;
            users[up].downlineNode += 1;
            up = users[up].upline;
        }
        c_erc20.addUserBuy(addr, 10**21);
        _addTeam(addr, 10**21);
    }

    function getTokenPrice() public view returns(uint256) {
        (uint reserveUSDT, uint reserveToken,) = IPancakePair(pair).getReserves();
        return 10**18*reserveUSDT/reserveToken;
    }

    function getReceivedRate(uint256 w, uint256 a) public view returns(uint256) {
        (uint reserveUSDT, ,) = IPancakePair(pair).getReserves();
        uint256 r = (w+a)*100/reserveUSDT;
        if(r < 2) { // w + a < reserveUSDT*2/100
            return 100;
        }
        if(r < 4) {
            return 90;
        }
        if(r < 6) {
            return 80;
        }
        if(r < 8) {
            return 70;
        }
        if(r < 10) {
            return 50;
        }
        return 30;
    }

    function getRedeemRate() public view returns(uint256, uint256) {
        (uint reserveUSDT, ,) = IPancakePair(pair).getReserves();
        if(reserveUSDT < 300*10**22) {
            return (30, 20);
        }
        if(reserveUSDT < 600*10**22) {
            return (45, 30);
        }
        if(reserveUSDT < 1000*10**22) {
            return (60, 40);
        }
        if(reserveUSDT < 1500*10**22) {
            return (70, 45);
        }
        if(reserveUSDT < 2000*10**22) {
            return (80, 50);
        }
        if(reserveUSDT < 2500*10**22) {
            return (90, 55);
        }
        if(reserveUSDT < 3000*10**22) {
            return (95, 60);
        }
        return (100, 70);
    }
    //核心：静态奖励领取
    function getStakeReward(uint256 idx) external {
        updateRewardRate();
        //取出第 idx 笔质押记录（StakeInfo）。
        StakeInfo memory o = stakes[msg.sender][idx];

        (uint256 sumRate, uint256 lastIdx, uint256 count) = getSumRewardRateLastIdxCount(o.rewardIdx, o.stakeDay - o.withdrawnDay);
        if(o.stakeAmount == 0 || count == 0 || (count < gbeRewardDay && o.stakeDay > o.withdrawnDay + count)) {
            revert InvalidAmount();
        }

        //计算从上次领取后到现在有多少天可以领取奖励
        stakes[msg.sender][idx].withdrawnDay = o.withdrawnDay + uint16(count);
        stakes[msg.sender][idx].rewardIdx = uint32(lastIdx);
        //收益计算：reward = stakeAmount * sumRate / 10000
        uint256 r = o.stakeAmount*sumRate/10000;
        //调用 _sendToken() 发放 NICE（或 mint c_good 替代）。
        _sendToken(msg.sender, r, r);
        //调用 _sendLevelReward() 给你的上级发放层级奖励，只记录数据，不实际发放代币。


        _sendLevelReward(msg.sender, r);
    }

    function getSumRewardRateLastIdxCount(uint256 startIdx, uint256 remainDay) public view returns(uint256, uint256, uint256) {
        uint256 len = rewardRates.length;
        uint256 r;
        uint256 c;
        for(uint256 i = startIdx+1; i < len; ++i) {
            if(c >= remainDay) {
                break;
            }
            r += rewardRates[i];
            ++c;
        }
        return (r, len-1, c);
    }

    function getSumRewardRateLastIdx(uint256 c) public view returns(uint256, uint256) {
        uint256 len = rewardRates.length;
        uint256 r;
        for(uint256 i = c+1; i < len; ++i) {
            r += rewardRates[i];
        }
        return (r, len-1);
    }

    function _sendLevelReward(address addr, uint256 amount) private {
        address up = users[addr].upline;
        uint256 curLevel;
        uint256 count = 1;
        for(uint256 i; i < 200; ++i) {
            if(up == address(0)) break;
            
            User storage s = users[up];
            if(count <= 15 && s.stakeAmount >= 10**20 && s.validDirectNum >= count) {
                s.refReward += amount/50;
                count++;
            }

            uint256 lvl = s.level;
            uint256 userlvl = calLevel(s.stakeAmount, s.smallArea);
            if(lvl < userlvl) {
                lvl = userlvl;
            }

            if(lvl > curLevel) {
                uint256 r = amount * (lvl - curLevel)/20;
                s.levelReward += r;
                curLevel = lvl;
            }
            up = s.upline;
        }
    }

    function calLevel(uint256 p, uint256 s) public pure returns(uint256){
        if(p >= 50000*10**18 && s >= 20000*10**22) {
            return 12;
        }
        if(p >= 40000*10**18 && s >= 10000*10**22) {
            return 11;
        }
        if(p >= 30000*10**18 && s >= 5000*10**22) {
            return 10;
        }
        if(p >= 20000*10**18 && s >= 2000*10**22) {
            return 9;
        }
        if(p >= 15000*10**18 && s >= 1000*10**22) {
            return 8;
        }
        if(p >= 10000*10**18 && s >= 500*10**22) {
            return 7;
        }
        if(p >= 8000*10**18 && s >= 200*10**22) {
            return 6;
        }
        if(p >= 5000*10**18 && s >= 75*10**22) {
            return 5;
        }
        if(p >= 3000*10**18 && s >= 25*10**22) {
            return 4;
        }
        if(p >= 2000*10**18 && s >= 5*10**22) {
            return 3;
        }
        if(p >= 1000*10**18 && s >= 10**22) {
            return 2;
        }
        if(p >= 500*10**18 && s >= 5*10**21) {
            return 1;
        }
        return 0;
    }
    //核心：动态奖励领取
    function getAllReward(uint256 redeemType) external {
        updateRewardRate();
        //取出你账户的 refReward + levelReward 总和（r）。
        User storage s = users[msg.sender];
        uint256 r = s.refReward + s.levelReward;
        if(r == 0 || block.timestamp < s.lastTime + gbeRewardDay*daySecond) {
            revert InvalidAmount();
        }
        //清零你的 refReward 和 levelReward，更新 lastTime。
        s.lastTime = block.timestamp;
        s.refReward = 0;
        s.levelReward = 0;
        //redeemType == 1：把奖励重新质押成新的一笔Stake（自动锁仓28天）。
        if(redeemType == 1) {
            stakes[msg.sender].push( StakeInfo(uint144(r), uint32(block.timestamp), uint32(rewardRates.length-1), uint16(gbeStakeDay), 0) );
            emit Stake(msg.sender, gbeStakeDay, stakes[msg.sender].length, r, block.timestamp);
            emit Transfer(address(0), msg.sender, r);
            s.stakeAmount += r;
            totalSupply += r;
            return;
        }
        //redeemType == 0（默认）
        //20% 铸造 c_ecv 给你（r/5）。
        uint256 ecvAmount = r/5;
        c_ecv.mint(msg.sender, ecvAmount);

        r -= ecvAmount;
        uint256 d = dynamicRewardStatus;
        //余80% 走 _sendToken() 发放 NICE。
        if(d > 2) {
            r = getReceivedRate(redeemAmount24h, r)*r/100;
        }
        if(d==2 || d==4) {
            redeemAmount24h += r;
        }
        _sendToken(msg.sender, r, r);
    }

    function skim() external {
        c_usdt.transfer(pair, c_usdt.balanceOf(address(this)));
        IPancakePair(pair).sync();
    }

    function contractInfo(uint256 stakeAmount) external view returns(uint256, uint256, uint256, uint256, uint256, uint256) {
        (uint reserveUSDT, ,) = IPancakePair(pair).getReserves();
        (uint256 rewardRate, uint256 redeemRate) = getRedeemRate();
        uint256 redeemAmount = stakeAmount*redeemRate/100;

        uint256 r24 = redeemAmount24h;
        if(block.timestamp >= rewardRateTime + daySecond) {
            r24 = 0;
        }
        uint256 receiveAmount = getReceivedRate(r24, redeemAmount)*redeemAmount/100;
        return (reserveUSDT, rewardRate, redeemRate, r24, redeemAmount, receiveAmount);
    }

    function contractInfo2() external view returns(uint256, uint256, uint256) {
        return (gbeStakeDay, gbeRewardDay, rewardRateTime);
    }

    function getLastIdx() external view returns(uint256) {
        return rewardRates.length - 1;
    }

    function rewardRateInfo() external view returns(uint256[] memory s) {
        s = rewardRates;
    }

    function userStakeInfo(address addr) external view returns(StakeInfo[] memory s) {
        s = stakes[addr];
    }

    function userDirects(address addr) external view returns(address[] memory s) {
        s = users[addr].directs;
    }

    function userStakeInfoByPage(address addr, uint256 pageNum, uint256 pageSize) external view returns(StakeInfo[] memory result, uint256 total) {
        StakeInfo[] storage sa = stakes[addr];
        total = sa.length;
        uint256 from = pageNum*pageSize;
        if (total <= from) {
            return (new StakeInfo[](0), total);
        }
        uint256 minNum = total - from < pageSize ? total - from : pageSize;
        from = total - from - 1;

        result = new StakeInfo[](minNum);
        for(uint256 i; i < minNum; i++) {
            result[i] = sa[from];
            if(from > 0) {
                from--;
            }
        }
    }

    function userInfo(address addr) external view returns(uint256, uint256, uint256, uint256, uint256, uint256, uint256, uint256) {
        User storage o = users[addr];
        uint256 ur = calLevel(o.stakeAmount, o.smallArea);
        return (o.level, o.validDirectNum, o.stakeAmount, o.smallArea, o.lastTime, o.refReward, o.levelReward, ur);
    }

    function userOtherInfo(address addr) external view returns(uint96, address, uint256, uint256, uint256, address, uint256) {
        User storage o = users[addr];
        return (o.id, o.upline, o.stakeSumUSDT, o.downline198, o.downline199, o.maxDirectAddr, o.downlineNode);
    }

    function getDirectsByPage(address addr, uint256 pageNum, uint256 pageSize) external view returns (address[] memory directAddrs, uint256[] memory personalAmounts, 
        uint256[] memory downlineAmounts, uint256[] memory stakeAmounts, uint256[] memory downlineNodes, uint256 total) {
        User storage s = users[addr];
        total = s.directs.length;
        uint256 from = pageNum*pageSize;
        if (total <= from) {
            return (new address[](0), new uint256[](0), new uint256[](0), new uint256[](0), new uint256[](0), total);
        }
        uint256 minNum = total - from < pageSize ? total - from : pageSize;

        directAddrs = new address[](minNum);
        personalAmounts = new uint256[](minNum);
        downlineAmounts = new uint256[](minNum);
        stakeAmounts = new uint256[](minNum);
        downlineNodes = new uint256[](minNum);
        
        for (uint256 i = 0; i < minNum; i++) {
            address one = s.directs[from++];
            directAddrs[i] = one;
            personalAmounts[i] = users[one].stakeSumUSDT;
            downlineAmounts[i] = users[one].downline198;
            stakeAmounts[i] = users[one].stakeAmount;
            downlineNodes[i] = users[one].downlineNode;
        }
    }
}