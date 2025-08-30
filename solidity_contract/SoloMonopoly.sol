// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract SoloMonopoly {
    string public constant name = "Solo Monopoly";
    string public constant symbol = "SMONO";
    uint8 public constant decimals = 18;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => Player) public players;
    mapping(address => uint256) public xmonoPoints;
    mapping(address => uint256) public nextRequiredSMONO; // In SMONO units (e.g., 1000), without decimals

    event Transfer(address indexed from, address indexed to, uint256 value);
    event GameStarted(address player);
    event DiceRolled(address player, uint256 roll, uint256 newPosition);
    event ProfitLanded(address player, uint256 reward);
    event LossLanded(address player, uint256 penalty);
    event ClaimedXmono(address player, uint256 points);

    uint256 private constant INITIAL_TOKENS = 500;
    uint256 private constant BOARD_SIZE = 16;

    enum TileType { NEUTRAL, PROFIT, LOSS }

    struct Tile {
        TileType tileType;
        int32 value;
        bytes12 name;
    }

    struct Player {
        uint8 position;
        bool hasStarted;
    }

    Tile[BOARD_SIZE] private board;
    bool private boardInitialized;

    constructor() {
        board[0] = Tile(TileType.NEUTRAL, 0, bytes12("Start"));
    }

    function startGame() external {
        require(!players[msg.sender].hasStarted, "Already playing");

        if (!boardInitialized) {
            _initializeBoard();
            boardInitialized = true;
        }

        _mint(msg.sender, INITIAL_TOKENS * (10 ** decimals));

        players[msg.sender] = Player({
            position: 0,
            hasStarted: true
        });
        nextRequiredSMONO[msg.sender] = 1000;

        emit GameStarted(msg.sender);
    }

    function rollDice() external {
        Player storage player = players[msg.sender];
        require(player.hasStarted, "Start game first");

        uint256 roll = _random() % 6 + 1;
        player.position = uint8((player.position + roll) % BOARD_SIZE);

        emit DiceRolled(msg.sender, roll, player.position);
        _handleLanding(msg.sender, player.position);
    }

    function claimXmono() external {
        Player storage player = players[msg.sender];
        require(player.hasStarted, "Start game first");

        uint256 required = nextRequiredSMONO[msg.sender] * (10 ** decimals);
        require(balanceOf[msg.sender] >= required, "Insufficient SMONO");

        balanceOf[msg.sender] -= required;
        totalSupply -= required;
        emit Transfer(msg.sender, address(0), required);

        xmonoPoints[msg.sender] += 1;
        emit ClaimedXmono(msg.sender, xmonoPoints[msg.sender]);

        nextRequiredSMONO[msg.sender] += 1000;
    }

    function _handleLanding(address playerAddr, uint8 position) internal {
        Tile memory tile = board[position];

        if (tile.tileType == TileType.PROFIT) {
            uint256 reward = uint256(uint32(tile.value)) * (10 ** decimals);
            _mint(playerAddr, reward);
            emit ProfitLanded(playerAddr, reward);
        } else if (tile.tileType == TileType.LOSS) {
            uint256 penalty = uint256(uint32(-tile.value)) * (10 ** decimals);
            if (balanceOf[playerAddr] >= penalty) {
                balanceOf[playerAddr] -= penalty;
                totalSupply -= penalty;
                emit Transfer(playerAddr, address(0), penalty);
                emit LossLanded(playerAddr, penalty);
            } else {
                emit LossLanded(playerAddr, balanceOf[playerAddr]);
                totalSupply -= balanceOf[playerAddr];
                balanceOf[playerAddr] = 0;
            }
        }
    }

    function _initializeBoard() private {
        board[1] = Tile(TileType.PROFIT, 150, bytes12("Airbnb Boost"));
        board[2] = Tile(TileType.LOSS, -50, bytes12("Lost Wallet"));
        board[3] = Tile(TileType.NEUTRAL, 0, bytes12("Park"));
        board[4] = Tile(TileType.PROFIT, 200, bytes12("Crypto Jack"));
        board[5] = Tile(TileType.LOSS, -50, bytes12("Car Repair"));
        board[6] = Tile(TileType.PROFIT, 175, bytes12("Freelance"));
        board[7] = Tile(TileType.LOSS, -30, bytes12("Stolen Phn"));
        board[8] = Tile(TileType.NEUTRAL, 0, bytes12("Relax Zone"));
        board[9] = Tile(TileType.PROFIT, 160, bytes12("E-Commerce"));
        board[10] = Tile(TileType.LOSS, -50, bytes12("Overdue Rt"));
        board[11] = Tile(TileType.PROFIT, 190, bytes12("Angel Inv"));
        board[12] = Tile(TileType.LOSS, -45, bytes12("Bad Trade"));
        board[13] = Tile(TileType.PROFIT, 130, bytes12("Gift Bonus"));
        board[14] = Tile(TileType.LOSS, -60, bytes12("Late Fee"));
        board[15] = Tile(TileType.NEUTRAL, 0, bytes12("Chill Spot"));
    }

    function _mint(address to, uint256 value) private {
        totalSupply += value;
        balanceOf[to] += value;
        emit Transfer(address(0), to, value);
    }

    function _random() private view returns (uint256) {
        return uint256(keccak256(abi.encodePacked(
            block.prevrandao,
            block.timestamp,
            msg.sender
        )));
    }

    function getTile(uint256 position) external view returns (string memory, TileType, int256) {
        require(position < BOARD_SIZE, "Invalid tile");
        Tile memory t = board[position];
        return (string(abi.encodePacked(t.name)), t.tileType, int256(t.value) * 1e18);
    }

    function getPlayerPosition(address player) external view returns (uint256) {
        return players[player].position;
    }
}
