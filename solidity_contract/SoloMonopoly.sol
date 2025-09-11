// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract SoloMonopoly {
    string public constant name = "Solo Monopoly";
    string public constant symbol = "SMONO";
    uint256 public totalSupply;

    // zkVerify contract address and verification key hash
    address public immutable zkvContract;
    bytes32 public immutable vkHash;
    bytes32 public constant PROVING_SYSTEM_ID = keccak256(abi.encodePacked("groth16"));

    mapping(address => uint256) public balanceOf;
    mapping(address => Player) public players;
    mapping(address => uint256) public xmonoPoints;
    mapping(address => uint256) public nextRequiredSMONO;

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

    constructor(address _zkvContract, bytes32 _vkHash) {
        zkvContract = _zkvContract;
        vkHash = _vkHash;
        board[0] = Tile(TileType.NEUTRAL, 0, bytes12("Start"));
    }

    function startGame() external {
        require(!players[msg.sender].hasStarted, "Already playing");

        if (!boardInitialized) {
            _initializeBoard();
            boardInitialized = true;
        }

        _mint(msg.sender, INITIAL_TOKENS);

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

    function verifyAndClaimXmono(
        uint256 attestationId,
        bytes32[] calldata merklePath,
        uint256 leafCount,
        uint256 index,
        uint256[3] memory input // [funds, nextRequiredSMONO, xmonoPoints]
    ) external {
        Player storage player = players[msg.sender];
        require(player.hasStarted, "Start game first");

        // Verify the proof attestation via zkVerify
        require(
            _verifyProofHasBeenPostedToZkv(
                attestationId,
                msg.sender,
                merklePath,
                leafCount,
                index,
                input
            ),
            "Invalid ZK proof attestation"
        );

        // Validate circuit inputs
        require(input[0] == 1, "Insufficient funds");
        require(input[1] == nextRequiredSMONO[msg.sender], "Invalid nextRequiredSMONO");
        require(input[2] == xmonoPoints[msg.sender], "Invalid xmonoPoints");

        uint256 required = nextRequiredSMONO[msg.sender];
        require(balanceOf[msg.sender] >= required, "Insufficient SMONO");

        // Burn required SMONO tokens
        balanceOf[msg.sender] -= required;
        totalSupply -= required;
        emit Transfer(msg.sender, address(0), required);

        // Award XMONO point
        xmonoPoints[msg.sender] += 1;
        emit ClaimedXmono(msg.sender, xmonoPoints[msg.sender]);

        // Update next required SMONO
        nextRequiredSMONO[msg.sender] += 1000;
    }

    function _verifyProofHasBeenPostedToZkv(
        uint256 attestationId,
        address inputAddress,
        bytes32[] calldata merklePath,
        uint256 leafCount,
        uint256 index,
        uint256[3] memory input
    ) internal view returns (bool) {
        // Construct the leaf: hash of PROVING_SYSTEM_ID, vkHash, and public inputs
        bytes memory encodedInput = abi.encodePacked(
            _changeEndianess(input[0]),
            _changeEndianess(input[1]),
            _changeEndianess(input[2])
        );
        bytes32 leaf = keccak256(
            abi.encodePacked(PROVING_SYSTEM_ID, vkHash, keccak256(encodedInput))
        );

        (bool callSuccessful, bytes memory validProof) = zkvContract.staticcall(
            abi.encodeWithSignature(
                "verifyProofAttestation(uint256,bytes32,bytes32[],uint256,uint256)",
                attestationId,
                leaf,
                merklePath,
                leafCount,
                index
            )
        );

        require(callSuccessful, "zkVerify contract call failed");

        return abi.decode(validProof, (bool));
    }

    function _changeEndianess(uint256 input) internal pure returns (uint256 v) {
        v = input;
        // Swap bytes
        v =
            ((v &
                0xFF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00) >>
                8) |
            ((v &
                0x00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF) <<
                8);
        // Swap 2-byte long pairs
        v =
            ((v &
                0xFFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000) >>
                16) |
            ((v &
                0x0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF) <<
                16);
        // Swap 4-byte long pairs
        v =
            ((v &
                0xFFFFFFFF00000000FFFFFFFF00000000FFFFFFFF00000000FFFFFFFF00000000) >>
                32) |
            ((v &
                0x00000000FFFFFFFF00000000FFFFFFFF00000000FFFFFFFF00000000FFFFFFFF) <<
                32);
        // Swap 8-byte long pairs
        v =
            ((v &
                0xFFFFFFFFFFFFFFFF0000000000000000FFFFFFFFFFFFFFFF0000000000000000) >>
                64) |
            ((v &
                0x0000000000000000FFFFFFFFFFFFFFFF0000000000000000FFFFFFFFFFFFFFFF) <<
                64);
        // Swap 16-byte long pairs
        v = (v >> 128) | (v << 128);
    }

    function _handleLanding(address playerAddr, uint8 position) internal {
        Tile memory tile = board[position];

        if (tile.tileType == TileType.PROFIT) {
            uint256 reward = uint256(uint32(tile.value));
            _mint(playerAddr, reward);
            emit ProfitLanded(playerAddr, reward);
        } else if (tile.tileType == TileType.LOSS) {
            uint256 penalty = uint256(uint32(-tile.value));
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
        return (string(abi.encodePacked(t.name)), t.tileType, int256(t.value));
    }

    function getPlayerPosition(address player) external view returns (uint256) {
        return players[player].position;
    }
}
