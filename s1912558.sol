// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.7.0 <0.9.0;

contract DiceRolling {

    struct Player {
        address payable addr;
        bytes32 commit;
        uint key;
        uint reward;
        bool reveal;
        bool withdraw;
    }

    uint constant TIMEOUT = 3600;
    uint256 public RollNumber;
    bool private gameClose;
    uint expiTime;
    bool noPlayer;

    mapping(address => Player) public GamePlayers;
    mapping(address => uint256) balance;
    // record address of the two player, Players[0] is the first player join the game
    address[2] Players;

    event Winner(address winner, uint RollNumber);
    event Reveal(address player, uint key);
    event Commit(address player, bytes32 commit);
    event Withdraw(address player, uint256 reward);
    
    // Modifiers
    modifier isPlayer() {
        require(msg.sender == GamePlayers[Players[0]].addr || msg.sender == GamePlayers[Players[1]].addr, 
        "You are not the player yet.");
        _;
    }
   
    modifier isJoinable() {
        require(Players[0] == address(0) || Players[1] == address(0), 
        "The game is full.");
        require(msg.sender != GamePlayers[Players[0]].addr && msg.sender != GamePlayers[Players[1]].addr, 
        "You are already a player.");
        _;
    }

    // if there are two players in the game
    modifier playerReady () {
        require(GamePlayers[Players[0]].addr != address(0) && GamePlayers[Players[1]].addr != address(0), 
        "Wait for player.");
        _;
    }
   
    // if the playGame function is called
    modifier isGameClose(){
        require(gameClose == false, "Your haven't play the game yet.");
        _;
    }

    modifier isFeeCorrect() {
        require(msg.value == 3 ether, "Please send fee must be 3.");
        _;
    }

    // if both player reveal the game
    modifier isReveal() {
        require(GamePlayers[Players[0]].reveal == true && GamePlayers[Players[1]].reveal == true, 
        "Wait for player to reveal.");
        _;
    }

    // if the game is expired or not
    modifier isTimeout() {
        require(expiTime > block.timestamp,
        "Time is over. Please use the function to withdraw your fee.");
        _;
    }

    // Functions
    function joinGame(bytes32 commit) public payable isJoinable() isFeeCorrect() {
        // first player
        if (Players[0] == address(0)){
            Players[0] = msg.sender;
            GamePlayers[Players[0]].addr = payable(msg.sender);
            GamePlayers[Players[0]].commit = commit;
            expiTime = block.timestamp + TIMEOUT;
        // second player
        } else {
            require(expiTime > block.timestamp,
            "Time is over. You cannot join the game.");
            Players[1] = msg.sender;
            GamePlayers[Players[1]].addr = payable(msg.sender);
            GamePlayers[Players[1]].commit = commit;
            // refresh the expired time
            expiTime = block.timestamp + TIMEOUT;
        }
        emit Commit(msg.sender, commit);
    }

    function gameReveal(uint key, bytes32 salt) public playerReady() isTimeout() {
        require(keccak256(abi.encodePacked(key, salt)) == GamePlayers[msg.sender].commit,
        "Reveal failed, invalid hash.");
        GamePlayers[msg.sender].reveal = true;
        GamePlayers[msg.sender].key = key;
        emit Reveal(msg.sender, key);
    }
    
    function playGame() public playerReady() isReveal() isTimeout() {
        // XOR the two player's key and has it
        RollNumber = uint(keccak256(abi.encodePacked(
            GamePlayers[Players[0]].key ^ GamePlayers[Players[1]].key))) % 6 + 1;
        address winner;
        // calculate the reward for each player
        if (RollNumber <= 3) {
            winner = Players[0];
            GamePlayers[Players[0]].reward = (3 + RollNumber) * 1 ether;
            GamePlayers[Players[1]].reward = (6 - (3 + RollNumber)) * 1 ether;
        } else {
            winner = Players[1];
            GamePlayers[Players[1]].reward = RollNumber * 1 ether;
            GamePlayers[Players[0]].reward = (6 - RollNumber) * 1 ether;
        }
        gameClose = true;
        emit Winner(winner, RollNumber);
    }
    
    function withdrawFees() public isPlayer() {
        // address of the caller
        address payable p = payable(msg.sender);
        // address of the other player
        address payable p2;
        if (p == Players[0]) {
            p2 = payable(Players[1]);
        } else {
            p2 = payable(Players[0]);
        }
        // timeout, no p2
        if (expiTime < block.timestamp && p2 == address(0)) {
            balance[p] = 0;
            noPlayer = true;
            p.transfer(3 ether);
            resetGame();
        // timeout, you revealed, p2 not
        } else if (expiTime < block.timestamp && GamePlayers[p].reveal == true 
        && GamePlayers[p2].reveal == false) {
            balance[p2] = 0;
            balance[p] = 0;
            GamePlayers[p].withdraw = true;
            GamePlayers[p2].withdraw = true;
            p.transfer(6 ether);
            emit Withdraw(msg.sender, GamePlayers[p].reward);
            resetGame();
        // timeout, whatever reveal or not
        } else if (expiTime < block.timestamp) {
            balance[p] = 0;
            balance[p2] = 0;
            GamePlayers[p].withdraw = true;
            GamePlayers[p2].withdraw = true;
            resetGame();
        // game played and finish
        } else if (gameClose == true) {
            balance[p] = 0;
            GamePlayers[p].withdraw = true;
            p.transfer(GamePlayers[p].reward);
            emit Withdraw(msg.sender, GamePlayers[p].reward);
            resetGame();
        }
    }

    function resetGame() private {
        // reset the player's data
        GamePlayers[msg.sender].addr = payable(address(0));
        GamePlayers[msg.sender].commit = 0;
        GamePlayers[msg.sender].reward = 0;
        GamePlayers[msg.sender].key = 0;
        GamePlayers[msg.sender].reveal = false;
        // both players withdraw the ether, reset the whole game
        if ((GamePlayers[Players[0]].withdraw == true 
        && GamePlayers[Players[1]].withdraw == true) || noPlayer == true) {
            GamePlayers[Players[0]].withdraw = false;
            GamePlayers[Players[1]].withdraw = false;
            delete Players[0];
            delete Players[1];
            delete Players;
            RollNumber = 0;
            gameClose = false;
            noPlayer = false;
        }
    }
}
