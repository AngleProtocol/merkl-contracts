// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.12;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../interfaces/ITreasury.sol";

struct MerkleTree {
    // Root of a Merkle tree which leaves are (address user, address token, uint amount)
    // representing an amount of tokens owed to user.
    // The Merkle tree is assumed to have only increasing amounts: that is to say if a user can claim 1,
    // then after the amount associated in the Merkle tree for this token should be x > 1
    bytes32 merkleRoot;
    // Ipfs hash of the tree data
    bytes32 ipfsHash;
}

/// @title OldMerkleRootDistributor
/// @notice Old pre-upgrade version of the MerkleRootDistributor contract
/// @author Angle Core Team
contract OldMerkleRootDistributor is Initializable {
    using SafeERC20 for IERC20;

    /// @notice Tree of claimable tokens through this contract
    MerkleTree public tree;

    /// @notice Treasury contract handling access control
    ITreasury public treasury;

    /// @notice Mapping user -> token -> amount to track claimed amounts
    mapping(address => mapping(address => uint256)) public claimed;

    /// @notice Trusted EOAs to update the merkle root
    mapping(address => uint256) public trusted;

    /// @notice Whether or not to enable permissionless claiming
    mapping(address => uint256) public whitelist;

    /// @notice user -> operator -> authorisation to claim
    mapping(address => mapping(address => uint256)) public operators;

    uint256[44] private __gap;

    // ================================== Events ===================================

    event TrustedToggled(address indexed eoa, bool trust);
    event Recovered(address indexed token, address indexed to, uint256 amount);
    event TreeUpdated(bytes32 merkleRoot, bytes32 ipfsHash);
    event Claimed(address user, address token, uint256 amount);
    event WhitelistToggled(address user, bool isEnabled);
    event OperatorToggled(address user, address operator, bool isWhitelisted);

    // ================================== Errors ===================================

    error InvalidLengths();
    error InvalidProof();
    error NotGovernorOrGuardian();
    error NotTrusted();
    error ZeroAddress();
    error NotWhitelisted();

    // ================================= Modifiers =================================

    /// @notice Checks whether the `msg.sender` has the governor role or the guardian role
    modifier onlyGovernorOrGuardian() {
        if (!treasury.isGovernorOrGuardian(msg.sender)) revert NotGovernorOrGuardian();
        _;
    }

    /// @notice Checks whether the `msg.sender` is a trusted address to change the Merkle root of the contract
    modifier onlyTrusted() {
        if (!treasury.isGovernorOrGuardian(msg.sender) && trusted[msg.sender] != 1) revert NotTrusted();
        _;
    }

    // ============================ Constructor ====================================

    constructor() initializer {}

    function initialize(ITreasury _treasury) public initializer {
        if (address(_treasury) == address(0)) revert ZeroAddress();
        treasury = _treasury;
    }

    // =========================== Main Function ===================================

    /// @notice Claims rewards for a given set of users
    /// @dev Anyone may call this function for anyone else, funds go to destination regardless, it's just a question of
    /// who provides the proof and pays the gas: `msg.sender` is not used in this function
    /// @param users Recipient of tokens
    /// @param tokens ERC20 claimed
    /// @param amounts Amount of tokens that will be sent to the corresponding users
    /// @param proofs Array of hashes bridging from leaf (hash of user | token | amount) to Merkle root
    function claim(
        address[] calldata users,
        address[] calldata tokens,
        uint256[] calldata amounts,
        bytes32[][] calldata proofs
    ) public {
        if (
            users.length == 0 ||
            users.length != tokens.length ||
            users.length != amounts.length ||
            users.length != proofs.length
        ) revert InvalidLengths();

        for (uint256 i = 0; i < users.length; i++) {
            address user = users[i];
            address token = tokens[i];
            uint256 amount = amounts[i];

            // Check whitelist if needed
            if (whitelist[user] == 1 && operators[user][msg.sender] == 0) revert NotWhitelisted();

            // Verifying proof
            bytes32 leaf = keccak256(abi.encode(user, token, amount));
            if (!_verifyProof(leaf, proofs[i])) revert InvalidProof();

            // Closing reentrancy gate here
            uint256 toSend = amount - claimed[user][token];
            claimed[user][token] = amount;

            IERC20(token).safeTransfer(user, toSend);
            emit Claimed(user, token, toSend);
        }
    }

    // =========================== Governance Functions ============================

    /// @notice Pull reward amount from caller
    //solhint-disable-next-line
    function deposit_reward_token(IERC20 token, uint256 amount) external {
        token.transferFrom(msg.sender, address(this), amount);
    }

    /// @notice Adds or removes trusted EOA
    function toggleTrusted(address eoa) external onlyGovernorOrGuardian {
        uint256 trustedStatus = 1 - trusted[eoa];
        trusted[eoa] = trustedStatus;
        emit TrustedToggled(eoa, trustedStatus == 1);
    }

    /// @notice Updates Merkle Tree
    function updateTree(MerkleTree calldata _tree) external onlyTrusted {
        tree = _tree;
        emit TreeUpdated(_tree.merkleRoot, _tree.ipfsHash);
    }

    /// @notice Toggles permissionless claiming for a given user
    function toggleWhitelist(address user) external {
        if (user != msg.sender && !treasury.isGovernorOrGuardian(msg.sender) && trusted[msg.sender] != 1)
            revert NotTrusted();
        whitelist[user] = 1 - whitelist[user];
        emit WhitelistToggled(user, whitelist[user] == 1);
    }

    /// @notice Toggles whitelisting for a given user and a given operator
    function toggleOperator(address user, address operator) external {
        if (user != msg.sender && !treasury.isGovernorOrGuardian(msg.sender) && trusted[msg.sender] != 1)
            revert NotTrusted();
        operators[user][operator] = 1 - operators[user][operator];
        emit OperatorToggled(user, operator, operators[user][operator] == 1);
    }

    /// @notice Recovers any ERC20 token
    function recoverERC20(
        address tokenAddress,
        address to,
        uint256 amountToRecover
    ) external onlyGovernorOrGuardian {
        IERC20(tokenAddress).safeTransfer(to, amountToRecover);
        emit Recovered(tokenAddress, to, amountToRecover);
    }

    // =========================== Internal Functions ==============================

    /// @notice Checks the validity of a proof
    /// @param leaf Hashed leaf data, the starting point of the proof
    /// @param proof Array of hashes forming a hash chain from leaf to root
    /// @return true If proof is correct, else false
    function _verifyProof(bytes32 leaf, bytes32[] memory proof) internal view returns (bool) {
        bytes32 currentHash = leaf;
        for (uint256 i = 0; i < proof.length; i += 1) {
            if (currentHash < proof[i]) {
                currentHash = keccak256(abi.encode(currentHash, proof[i]));
            } else {
                currentHash = keccak256(abi.encode(proof[i], currentHash));
            }
        }
        return currentHash == tree.merkleRoot;
    }
}
