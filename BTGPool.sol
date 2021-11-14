pragma solidity >=0.5.0 <0.8.0;

import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";

contract BTGPool {

    address public owner;
    IERC20 public btg;
    IERC20 public usdt;
    uint public runStatus;
    uint public dateTime;
    uint public auctionNum;
    uint public bonusNum;

    event Invite(address indexed addr, address inviter, uint index);

    event Play(address indexed addr, uint period, uint guess, uint amount, uint index);

    event Offer(address indexed addr, uint day, uint amount);

    event Answer(uint period, uint answer);

    event Next(uint period);

    struct Developer{
        address addr;
        uint amount;
    }

    Developer[] public developers;

    function setDevelopers(address[] memory _developers, uint[] memory amounts) public onlyOwner{
        require(developers.length == 0 , "BTG:Developers have been set");
        require(_developers.length == amounts.length, "BTG:Invalid parameter");
        uint totalAmount;
        for(uint i; i < amounts.length; i++){
            totalAmount += amounts[i];
        }
        require(totalAmount == 14*10**20, "BTG:Invalid parameter");
        for(uint j; j < _developers.length; j++){
            developers.push(Developer(_developers[j], amounts[j]));
        }
    }

    mapping(uint => bool) public bonusMap;

    address[] public userArray;

    mapping(address => address) public inviteMap;

    struct Quiz{
        uint index;
        address player;
        uint period;
        uint amount;
        uint guess;
        bool finish;
    }

    Quiz[] public quizArray;

    function getUncheckGuessArray(address addr) public view returns(uint[] memory){
        uint count = 0;
        for(uint i; i < quizArray.length; i++){
            if(quizArray[i].player == addr && quizArray[i].guess == periodMap[quizArray[i].period].answer && quizArray[i].finish == false){
                count++;
            }
        }
        uint[] memory uncheckArray = new uint[](count);
        if(count != 0){
            for(uint i; i < quizArray.length; i++){
                if(quizArray[i].player == addr && quizArray[i].guess == periodMap[quizArray[i].period].answer && quizArray[i].finish == false){
                    uncheckArray[count-1] = i;
                    count--;
                }
            }
        }
        return uncheckArray;
    }

    struct Operate{
        uint amount;
        uint action; //0.无操作 1.连续做市 2.做市一轮 3.取消做市 4.取消预约
        uint backAmount;
    }

    mapping(uint => mapping(address => Operate)) public operateMap;

    mapping(uint => address[]) public hostMap;

    function getHostArray(uint round) public view returns(address[] memory){
        return hostMap[round];
    }

    struct Auction{
        uint amount;
        bool success;
        bool finish;
    }

    mapping(uint => mapping(address => Auction)) public auctionMap;

    mapping(uint => address[]) public auctioneerMap;

    function getAuctioneerArray(uint day) public view returns(address[] memory){
        return auctioneerMap[day];
    }

    mapping(address => uint[]) public offerMap;

    function getOfferArray(address addr) public view returns(uint[] memory){
        return offerMap[addr];
    }

    function getUncheckOfferArray(address addr) public view returns(uint[] memory){
        uint[] memory dayList = offerMap[addr];
        uint count = 0;
        for(uint i; i < dayList.length; i++){
            if(auctionMap[dayList[i]][addr].finish == false && dayList[i] < dateTime/10000){
                count++;
            }
        }
        uint[] memory uncheckArray = new uint[](count);
        if(count != 0){
            for(uint i; i < dayList.length; i++){
                if(auctionMap[dayList[i]][addr].finish == false && dayList[i] < dateTime/10000){
                    uncheckArray[count-1] = dayList[i];
                    count--;
                }
            }
        }
        return uncheckArray;
    }

    function getPeriodReward(address addr, uint period) public view returns(uint[] memory){
        uint[] memory result = new uint[](2);
        uint count = 0;
        uint amount = 0;
        for(uint i; i < quizArray.length; i++){
            if(quizArray[i].player == addr && quizArray[i].period == period){
                count++;
                if(quizArray[i].guess == periodMap[period].answer){
                    if(quizArray[i].guess == 1 || quizArray[i].guess == 2){
                        amount += quizArray[i].amount * 21 / 10;
                    }else if(quizArray[i].guess == 3){
                        amount += quizArray[i].amount * 94 / 10;
                    }
                }
            }
        }
        result[0] = count;
        result[1] = amount;
        return result;
    }

    struct Profit{
        uint dateTime;
        address receiver;
        uint btgAmount;
        uint usdtAmount;
    }

    Profit[] public profitArray;

    struct Period{
        uint amount1;
        uint amount2;
        uint amount3;
        uint openBlock;
        uint answer;
    }

    mapping(uint => Period) public periodMap;

    struct Round{
        uint hostAmount;
        uint hostWin;
        uint hostLoss;
        bool playBonus;
    }

    mapping(uint => Round) public roundMap;

    constructor(IERC20 _btg, IERC20 _usdt) public{
        owner = msg.sender;
        btg = _btg;
        usdt = _usdt;
        inviteMap[address(this)] = address(this);
    }

    mapping(address => bool) public senderMap;

    function setSender(address sender, bool isSender) public onlyOwner{
        senderMap[sender] = isSender;
    }

    modifier onlySender{
        require(senderMap[msg.sender], "BTG:Caller is not the sender");
        _;
    }

    modifier onlyOwner{
        require(msg.sender == owner, "BTG:Caller is not the owner");
        _;
    }

    modifier onlyRun{
        require(runStatus == 1, "BTG:The game is not running");
        _;
    }

    modifier notStop{
        require(runStatus != 0, "BTG:The game is stopping");
        _;
    }

    modifier notSettle{
        require(dateTime % 100 < 12, "BTG:The game is settling");
        _;
    }

    modifier needAllowance(uint amount){
        require(amount % 10**18 == 0, "BTG:Amount must be an integer");
        require(usdt.balanceOf(msg.sender) >= amount, "BTG:Amount exceeds your balance of USDT");
        require(usdt.allowance(msg.sender, address(this)) >= amount, "BTG:Please approve the game");
        _;
    }

    function sendBonus() public onlyOwner{
        require(bonusNum < 500, "BTG:The bonus is over");
        require(bonusMap[dateTime/10000] == false, "BTG:The bonus has been sent");
        require(developers.length > 0, "BTG:Please set developers");
        for(uint i; i < developers.length; i++){
            btg.transfer(developers[i].addr, developers[i].amount);
        }
        bonusNum++;
        bonusMap[dateTime/10000] = true;
    }

    function setDateTime(uint _dateTime) public onlyOwner{
        periodMap[dateTime].openBlock = block.number;
        dateTime = _dateTime;
        emit Next(dateTime);
    }

    function setRunStatus(uint _runStatus) public onlyOwner{
        runStatus = _runStatus;
    }

    function acceptInvitation(address inviter) public notStop{
        require(inviteMap[msg.sender] == address(0), "BTG:Invitation cannot be accepted repeatedly");
        require(inviteMap[inviter] != address(0), "BTG:The invitee was not invited");
        inviteMap[msg.sender] = inviter;
        userArray.push(msg.sender);
        emit Invite(msg.sender, inviter, userArray.length - 1);
    }

    function sendProfit(address addr, uint btgAmount, uint usdtAmount) public onlySender{
        if(btgAmount != 0){
            btg.transfer(addr, btgAmount);
        }
        if(usdtAmount != 0){
            usdt.transfer(addr, usdtAmount);
        }
        profitArray.push(Profit(dateTime, addr, btgAmount, usdtAmount));
    }

    function revealAnswer(uint period, uint answer) public onlyOwner{
        require(periodMap[period].openBlock != 0, 'BTG:Please set openBlock');
        require(periodMap[period].answer == 0, 'BTG:The answer has been revealed');
        require(1 <= answer && answer <= 3, "BTG:Invalid parameter");
        uint hostWin = (periodMap[period].amount1 + periodMap[period].amount2 + periodMap[period].amount3) * 99 / 100;
        uint hostLoss = 0;
        if(answer == 1){
            hostLoss += periodMap[period].amount1 * 21 / 10;
        }else if(answer == 2){
            hostLoss += periodMap[period].amount2 * 21 / 10;
        }else if(answer == 3){
            hostLoss += periodMap[period].amount3 * 94 / 10;
        }
        periodMap[period].answer = answer;
        roundMap[period/100].hostWin += hostWin;
        roundMap[period/100].hostLoss += hostLoss;
        emit Answer(period, answer);
    }

    function setHostAmount(uint round, uint hostAmount, bool playBonus) public onlyOwner{
        roundMap[round].hostAmount = hostAmount;
        roundMap[round].playBonus = playBonus;
    }

    function playLimit() public view returns(uint[] memory){
        uint[] memory limits = new uint[](4);
        limits[0] = roundMap[dateTime/100].hostAmount / 10 ** 18;
        limits[1] = (roundMap[dateTime/100].hostAmount / 50 - periodMap[dateTime].amount1) / 10**18;
        limits[2] = (roundMap[dateTime/100].hostAmount / 50 - periodMap[dateTime].amount2) / 10**18;
        limits[3] = (roundMap[dateTime/100].hostAmount / 1000 - periodMap[dateTime].amount3) / 10**18;
        return limits;
    }

    function play(uint amount, uint guess) public onlyRun notSettle needAllowance(amount){
        require(amount >= 10**18, "BTG:Amount must be more than 1 USDT");
        require(1 <= guess && guess <= 3, "BTG:Invalid parameter");
        if(inviteMap[msg.sender] == address(0)){
            acceptInvitation(address(this));
        }
        if(guess == 1){
            require(amount + periodMap[dateTime].amount1 <= roundMap[dateTime/100].hostAmount / 50, "BTG:Amount of quiz exceeds limit");
            periodMap[dateTime].amount1 += amount;
        }else if(guess == 2){
            require(amount + periodMap[dateTime].amount2 <= roundMap[dateTime/100].hostAmount / 50, "BTG:Amount of quiz exceeds limit");
            periodMap[dateTime].amount2 += amount;
        }else if(guess == 3){
            require(amount + periodMap[dateTime].amount3 <= roundMap[dateTime/100].hostAmount / 1000, "BTG:Amount of quiz exceeds limit");
            periodMap[dateTime].amount3 += amount;
        }
        usdt.transferFrom(msg.sender, address(this), amount);
        quizArray.push(Quiz(quizArray.length, msg.sender, dateTime, amount, guess, false));
        emit Play(msg.sender, dateTime, guess, amount, quizArray.length - 1);
    }

    function getReward(uint index) public onlyRun{
        require(quizArray[index].player == msg.sender, "BTG:Caller is not the player");
        require(quizArray[index].guess == periodMap[quizArray[index].period].answer, "BTG:You didn't guess right");
        require(quizArray[index].finish == false, "BTG:The Quiz awards has been receive");
        quizArray[index].finish = true;
        if(quizArray[index].guess == 1 || quizArray[index].guess == 2){
            usdt.transfer(msg.sender, quizArray[index].amount * 21 / 10);
        }else if(quizArray[index].guess == 3){
            usdt.transfer(msg.sender, quizArray[index].amount * 94 / 10);
        }
    }

    function getRewardBatch() public onlyRun{
        uint[] memory indexes = getUncheckGuessArray(msg.sender);
        uint amount = 0;
        for(uint i; i < indexes.length; i++){
            if(quizArray[indexes[i]].guess == 1 || quizArray[indexes[i]].guess == 2){
                amount += quizArray[indexes[i]].amount * 21 / 10;
            }else if(quizArray[indexes[i]].guess == 3){
                amount += quizArray[indexes[i]].amount * 94 / 10;
            }
        }
        if(amount > 0){
            usdt.transfer(msg.sender, amount);
        }
    }

    function offer(uint amount) public onlyRun needAllowance(amount){
        require(amount >= 10**20, "BTG:Amount must be more than 100 USDT");
        require(auctionNum < 15000, "BTG:The auction is over");
        require(auctionMap[dateTime/10000][msg.sender].amount == 0, "BTG:You have offered price");
        if(inviteMap[msg.sender] == address(0)){
            acceptInvitation(address(this));
        }
        usdt.transferFrom(msg.sender, address(this), amount);
        auctioneerMap[dateTime/10000].push(msg.sender);
        offerMap[msg.sender].push(dateTime/10000);
        auctionMap[dateTime/10000][msg.sender].amount = amount;
        emit Offer(msg.sender, dateTime/10000, auctionMap[dateTime/10000][msg.sender].amount);
    }

    function offerMore(uint amount) public onlyRun needAllowance(amount){
        require(auctionMap[dateTime/10000][msg.sender].amount >= 10**20, "BTG:Please offer price first");
        require(amount >= 10**18, "BTG:Amount must be more than 1 USDT");
        usdt.transferFrom(msg.sender, address(this), amount);
        auctionMap[dateTime/10000][msg.sender].amount += amount;
        emit Offer(msg.sender, dateTime/10000, auctionMap[dateTime/10000][msg.sender].amount);
    }

    function setSuccess(uint day, address[] memory auctioneers) public onlyOwner{
        for(uint i; i < auctioneers.length; i++){
            if(auctionMap[day][auctioneers[i]].success == false && auctionMap[day][auctioneers[i]].amount > 0){
                auctionMap[day][auctioneers[i]].success = true;
                auctionNum++;
            }
        }
    }

    function getAuction(uint day) public onlyRun{
        require(day < dateTime/10000, "BTG:The Auction does not finish");
        require(auctionMap[day][msg.sender].amount > 0, 'BTG:The auction does not exist');
        require(auctionMap[day][msg.sender].finish == false, "BTG:The auction has been confirmed");
        auctionMap[day][msg.sender].finish = true;
        if(auctionMap[day][msg.sender].success){
            btg.transfer(msg.sender, 10**20);
        }else{
            usdt.transfer(msg.sender, auctionMap[day][msg.sender].amount);
        }
    }

    function getAuctionBatch() public onlyRun{
        uint[] memory dayList = getUncheckOfferArray(msg.sender);
        uint usdtAmount = 0;
        uint btgAmount = 0;
        for(uint i = 0; i < dayList.length; i++){
            auctionMap[dayList[i]][msg.sender].finish = true;
            if(auctionMap[dayList[i]][msg.sender].success){
                btgAmount += 10**20;
            }else{
                usdtAmount += auctionMap[dayList[i]][msg.sender].amount;
            }
        }
        if(usdtAmount > 0){
            usdt.transfer(msg.sender, usdtAmount);
        }
        if(btgAmount > 0){
            btg.transfer(msg.sender, btgAmount);
        }
    }

    function host(uint amount) public notStop notSettle needAllowance(amount){
        if(inviteMap[msg.sender] == address(0)){
            acceptInvitation(address(this));
        }
        if(operateMap[dateTime/100][msg.sender].action == 0){
            hostMap[dateTime/100].push(msg.sender);
        }
        usdt.transferFrom(msg.sender, address(this), amount);
        operateMap[dateTime/100][msg.sender].amount += amount;
        operateMap[dateTime/100][msg.sender].action = 1;
    }

    function hostOnce(uint amount) public notStop notSettle needAllowance(amount){
        if(inviteMap[msg.sender] == address(0)){
            acceptInvitation(address(this));
        }
        if(operateMap[dateTime/100][msg.sender].action == 0){
            hostMap[dateTime/100].push(msg.sender);
        }
        usdt.transferFrom(msg.sender, address(this), amount);
        operateMap[dateTime/100][msg.sender].amount += amount;
        operateMap[dateTime/100][msg.sender].action = 2;
    }

    function cancel() public notStop notSettle{
        if(inviteMap[msg.sender] == address(0)){
            acceptInvitation(address(this));
        }
        if(operateMap[dateTime/100][msg.sender].action == 0){
            hostMap[dateTime/100].push(msg.sender);
        }
        operateMap[dateTime/100][msg.sender].action = 3;
        if(operateMap[dateTime/100][msg.sender].amount != 0){
            usdt.transfer(msg.sender, operateMap[dateTime/100][msg.sender].amount);
            operateMap[dateTime/100][msg.sender].amount = 0;
        }
    }

    //取消预约,action=4 等价于 action=0
    function cancelReservation() public notStop notSettle{
        if(inviteMap[msg.sender] == address(0)){
            acceptInvitation(address(this));
        }
        operateMap[dateTime/100][msg.sender].action = 4;
        if(operateMap[dateTime/100][msg.sender].amount != 0){
            usdt.transfer(msg.sender, operateMap[dateTime/100][msg.sender].amount);
            operateMap[dateTime/100][msg.sender].amount = 0;
        }
    }

    function remand(uint round, address addr, uint amount) public onlySender{
        usdt.transfer(addr, amount);
        operateMap[round][addr].backAmount += amount;
    }

    //获取前limit名竞拍
//    function getTop(uint day, uint limit) public view returns(address[] memory, uint[] memory){
//        if(auctioneerMap[day].length < limit){
//            limit = auctioneerMap[day].length;
//        }
//        address[] memory auctioneers = new address[](limit);
//        uint[] memory amounts = new uint[](limit);
//        for(uint i; i < auctioneerMap[day].length; i++){
//            uint index = limit;
//            for(uint j; j < limit; j++){
//                if(amounts[j] < auctionMap[day][auctioneerMap[day][i]].amount){
//                    index = j;
//                    break;
//                }
//            }
//            for(uint k = limit - 1; k > index ; k--){
//                amounts[k] = amounts[k-1];
//                auctioneers[k] = auctioneers[k-1];
//            }
//            if(index != limit){
//                auctioneers[index] = auctioneerMap[day][i];
//                amounts[index] = auctionMap[day][auctioneerMap[day][i]].amount;
//            }
//        }
//        return (auctioneers, amounts);
//    }

//    function getRank(uint day, address addr) public view returns(uint, uint){
//        uint rank;
//        uint amount;
//        (address[] memory auctioneers, uint[] memory amounts) = getTop(day, auctioneerMap[day].length);
//        if(auctioneers.length > 0){
//            for(uint i; i < auctioneers.length; i++){
//                if(auctioneers[i] == addr){
//                    rank = i+1;
//                    amount = amounts[i];
//                    break;
//                }
//            }
//        }
//        return (rank, amount);
//    }

//    function auctionSettle(uint day) public onlyOwner{
//        require(15000 > auctionNum, "BTG:The auction is over");
//        uint limit = 15000 - auctionNum > 30 ? 30 : 15000 - auctionNum;
//        (address[] memory auctioneers, uint[] memory amounts) = getTop(day, limit);
//        for(uint i; i < amounts.length; i++){
//            if(auctionMap[day][auctioneers[i]].success == false && auctionMap[day][auctioneers[i]].amount > 0){
//                auctionMap[day][auctioneers[i]].success = true;
//                auctionNum++;
//            }
//        }
//    }

//    function getAuctionResult(uint day) public view returns(uint, uint, uint, uint){
//        uint successNum;
//        uint auctionAmount;
//        uint auctionAvg;
//        uint auctionMax;
//        for(uint i; i < auctioneerMap[day].length; i++){
//            if(auctionMap[day][auctioneerMap[day][i]].success){
//                successNum++;
//                auctionAmount += auctionMap[day][auctioneerMap[day][i]].amount;
//                if(auctionMap[day][auctioneerMap[day][i]].amount > auctionMax){
//                    auctionMax = auctionMap[day][auctioneerMap[day][i]].amount;
//                }
//            }
//        }
//        if(successNum == 0){
//            auctionMax = 10**20;
//            auctionAvg = 10**20;
//        }else{
//            auctionAvg = auctionAmount / successNum;
//        }
//        return (auctionAmount, successNum, auctionAvg, auctionMax);
//    }

    //返回 领奖索引/期数/投注数量/竞猜/谜底/领取
//    function filterQuizArray(address player, uint day) public view returns(uint[] memory, uint[] memory, uint[] memory, uint[] memory, uint[] memory, bool[] memory){
//        uint count = 0;
//        for(uint i; i < quizArray.length; i++){
//            if(quizArray[i].player == player
//                && (day == 0 || quizArray[i].period/10000 == day)){
//                count++;
//            }
//        }
//        uint[] memory indexArray = new uint[](count);
//        uint[] memory periodArray = new uint[](count);
//        uint[] memory amountArray = new uint[](count);
//        uint[] memory guessArray = new uint[](count);
//        uint[] memory answerArray = new uint[](count);
//        bool[] memory finishArray = new bool[](count);
//        if(count > 0){
//            for(uint i; i < quizArray.length; i++){
//                if(quizArray[i].player == player
//                    && (day == 0 || quizArray[i].period/10000 == day)){
//                    count--;
//                    indexArray[count] = quizArray[i].index;
//                    periodArray[count] = quizArray[i].period;
//                    amountArray[count] = quizArray[i].amount;
//                    guessArray[count] = quizArray[i].guess;
//                    answerArray[count] = periodMap[quizArray[i].period].answer;
//                    finishArray[count] = quizArray[i].finish;
//                }
//            }
//        }
//        return (indexArray, periodArray, amountArray, guessArray, answerArray, finishArray);
//    }

    //期数，名次，数量，成功，领取
//    function filterAuctionArray() public view returns(uint[] memory, uint[] memory, uint[] memory, bool[] memory, bool[] memory){
//        uint count = offerMap[msg.sender].length;
//        uint[] memory periodArray = new uint[](count);
//        uint[] memory rankArray = new uint[](count);
//        uint[] memory amountArray = new uint[](count);
//        bool[] memory successArray = new bool[](count);
//        bool[] memory finishArray = new bool[](count);
//        if(count > 0){
//            for(uint i; i < offerMap[msg.sender].length; i++){
//                count--;
//                periodArray[count] = offerMap[msg.sender][i];
//                (rankArray[count], amountArray[count]) = getRank(offerMap[msg.sender][i], msg.sender);
//                successArray[count] = auctionMap[offerMap[msg.sender][i]][msg.sender].success;
//                finishArray[count] = auctionMap[offerMap[msg.sender][i]][msg.sender].finish;
//            }
//        }
//        return (periodArray, rankArray, amountArray, successArray, finishArray);
//    }

}
