// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { UUPSHelper } from "./utils/UUPSHelper.sol";
import { IAccessControlManager } from "./interfaces/IAccessControlManager.sol";
import { Errors } from "./utils/Errors.sol";

/// @title ReferralRegistry
/// @notice Allows to manage referral programs and claim rewards distributed through Merkl
/// @dev This contract uses UUPS upgradeability pattern and ReentrancyGuard for security
contract ReferralRegistry is UUPSHelper {
    using SafeERC20 for IERC20;
    struct ReferralProgram {
        address owner;
        bool requiresAuthorization;
        bool requiresRefererToBeSet;
        uint256 cost;
        address paymentToken;
    }
    enum ReferralStatus {
        NotAllowed,
        Allowed,
        Set
    }

    /// @notice Address to receive fees
    address public feeRecipient;

    /// @notice `AccessControlManager` contract handling access control
    IAccessControlManager public accessControlManager;

    /// @notice Whether the contract has been made non upgradeable or not
    uint128 public upgradeabilityDeactivated;

    /// @notice Cost to create a referral program
    uint256 public costReferralProgram;

    /// @notice List of bytes keys that are currently in a referral program
    bytes[] public referralKeys;

    /// @notice Mapping to store referral program details
    mapping(bytes => ReferralProgram) public referralPrograms;

    /// @notice Mapping to determine if a user is allowed to be a referrer
    mapping(bytes => mapping(address => ReferralStatus)) public refererStatus;

    /// @notice Mapping to store referrer codes
    mapping(bytes => mapping(address => string)) public referrerCodeMapping;

    /// @notice Mapping to store referrer addresses by code
    mapping(bytes => mapping(string => address)) public codeToReferrer;

    /// @notice Mapping to store user to referrer relationships
    mapping(bytes => mapping(address => address)) public keyToUserToReferrer;

    /// @notice Adds a new referral key to the list
    /// @param key The referral key to add
    /// @param _cost The cost of the referral program
    /// @param _requiresRefererToBeSet Whether the referral program requires a referrer to be set
    /// @param _owner The owner of the referral program
    /// @param _requiresAuthorization Whether the referral program requires authorization
    /// @param _paymentToken The token used for payment in the referral program
    function addReferralKey(
        bytes calldata key,
        uint256 _cost,
        bool _requiresRefererToBeSet,
        address _owner,
        bool _requiresAuthorization,
        address _paymentToken
    ) external payable {
        if (referralPrograms[key].owner != address(0)) revert Errors.KeyAlreadyUsed();
        if (msg.value != costReferralProgram) revert Errors.NotEnoughPayment();
        if (costReferralProgram > 0) {
            payable(feeRecipient).transfer(msg.value);
        }
        referralKeys.push(key);
        require(
            _cost == 0 || (_cost > 0 && _requiresRefererToBeSet),
            "Cost must be set if requiresRefererToBeSet is true"
        );
        referralPrograms[key] = ReferralProgram({
            owner: _owner,
            requiresAuthorization: _requiresAuthorization,
            cost: _cost,
            requiresRefererToBeSet: _requiresRefererToBeSet,
            paymentToken: _paymentToken
        });
        emit ReferralKeyAdded(key);
    }

    /// @notice Edits the parameters of a referral program
    /// @param key The referral key to edit
    /// @param newCost The new cost of the referral program
    /// @param newRequiresAuthorization Whether the referral program requires authorization
    /// @param newRequiresRefererToBeSet Whether the referral program requires a referrer to be set
    /// @param newPaymentToken The new payment token of the referral program
    function editReferralProgram(
        bytes calldata key,
        uint256 newCost,
        bool newRequiresAuthorization,
        bool newRequiresRefererToBeSet,
        address newPaymentToken
    ) external {
        if (referralPrograms[key].owner != msg.sender) revert Errors.NotAllowed();
        referralPrograms[key] = ReferralProgram({
            owner: referralPrograms[key].owner,
            requiresAuthorization: newRequiresAuthorization,
            cost: newCost,
            requiresRefererToBeSet: newRequiresRefererToBeSet,
            paymentToken: newPaymentToken
        });
        emit ReferralProgramModified(
            key,
            newCost,
            newRequiresAuthorization,
            newRequiresRefererToBeSet,
            newPaymentToken
        );
    }

    /// @notice Allows a user to become a referrer for a specific referral key
    /// @param key The referral key for which the user wants to become a referrer
    /// @param referrerCode The code of the referrer
    function becomeReferrer(bytes calldata key, string calldata referrerCode) external payable {
        ReferralProgram storage program = referralPrograms[key];
        if (program.cost > 0) {
            if (address(program.paymentToken) == address(0)) {
                if (msg.value != program.cost) revert Errors.NotEnoughPayment();
                payable(program.owner).transfer(msg.value);
            } else {
                IERC20(program.paymentToken).safeTransferFrom(msg.sender, program.owner, program.cost);
            }
        }
        if (program.requiresAuthorization) {
            if (refererStatus[key][msg.sender] != ReferralStatus.Allowed) revert Errors.NotAllowed();
        }
        refererStatus[key][msg.sender] = ReferralStatus.Set;
        require(codeToReferrer[key][referrerCode] == address(0), "Referrer code already in use");
        referrerCodeMapping[key][msg.sender] = referrerCode;
        codeToReferrer[key][referrerCode] = msg.sender;
        emit ReferrerAdded(key, msg.sender);
    }

    /// @notice Allows a user to acknowledge that they are referred by a referrer
    /// @param key The referral key for which the user is acknowledging the referrer
    /// @param referrer The address of the referrer
    function acknowledgeReferrer(bytes calldata key, address referrer) public {
        if (referralPrograms[key].requiresRefererToBeSet) {
            require(refererStatus[key][referrer] == ReferralStatus.Set, "Referrer has not created a referral link");
        }
        keyToUserToReferrer[key][msg.sender] = referrer;
        emit ReferrerAcknowledged(key, msg.sender, referrer);
    }

    /// @notice Allows a user to acknowledge that they are referred by a referrer using a referrer code
    /// @param key The referral key for which the user is acknowledging the referrer
    /// @param referrerCode The code of the referrer
    function acknowledgeReferrerByKey(bytes calldata key, string calldata referrerCode) external {
        address referrer = codeToReferrer[key][referrerCode];
        acknowledgeReferrer(key, referrer);
    }

    /// @notice Sets the cost of the referral program
    /// @param _costReferralProgram The new cost of the referral program
    function setCostReferralProgram(uint256 _costReferralProgram) external onlyGovernor {
        costReferralProgram = _costReferralProgram;
        emit CostReferralProgramSet(_costReferralProgram);
    }

    /// @notice Receive function to accept ETH payments
    receive() external payable {
        // Custom logic for receiving ETH can be added here
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        EVENTS                                                      
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/
    event CostReferralProgramSet(uint256 newCost);
    event ReferrerAcknowledged(bytes indexed key, address indexed user, address indexed referrer);
    event ReferrerAdded(bytes indexed key, address indexed referrer);
    event ReferralProgramModified(
        bytes indexed key,
        uint256 newCost,
        bool newRequiresAuthorization,
        bool newRequiresRefererToBeSet,
        address newPaymentToken
    );
    event ReferralKeyAdded(bytes indexed key);
    event ReferralKeyRemoved(uint256 index);
    event UpgradeabilityRevoked();

    event Claimed(address indexed user, address indexed token, uint256 amount);

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                       MODIFIERS                                                    
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    /// @notice Checks whether the `msg.sender` has the governor role
    modifier onlyGovernor() {
        if (!accessControlManager.isGovernor(msg.sender)) revert Errors.NotGovernor();
        _;
    }

    /// @notice Checks whether the contract is upgradeable or whether the caller is allowed to upgrade the contract
    modifier onlyUpgradeableInstance() {
        if (upgradeabilityDeactivated == 1) revert Errors.NotUpgradeable();
        else if (!accessControlManager.isGovernor(msg.sender)) revert Errors.NotGovernor();
        _;
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                      CONSTRUCTOR                                                   
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    constructor() initializer {}
    function initialize(
        IAccessControlManager _accessControlManager,
        uint256 _costReferralProgram,
        address _feeRecipient
    ) external initializer {
        if (address(_accessControlManager) == address(0)) revert Errors.ZeroAddress();
        accessControlManager = _accessControlManager;
        costReferralProgram = _costReferralProgram;
        feeRecipient = _feeRecipient;
    }

    /// @inheritdoc UUPSHelper
    function _authorizeUpgrade(address) internal view override onlyUpgradeableInstance {}

    /// @notice Prevents future contract upgrades
    function revokeUpgradeability() external onlyGovernor {
        upgradeabilityDeactivated = 1;
        emit UpgradeabilityRevoked();
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                      VIEW FUNCTIONS                                                   
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    /// @notice Gets the list of referral keys
    /// @return The list of referral keys
    function getReferralKeys() external view returns (bytes[] memory) {
        return referralKeys;
    }
    /// @notice Gets the details of a referral program
    /// @param key The referral key to get details for
    /// @return The details of the referral program
    function getReferralProgram(bytes calldata key) external view returns (ReferralProgram memory) {
        return referralPrograms[key];
    }

    /// @notice Gets the referrer status for a specific user and referral key
    /// @param key The referral key to check
    /// @param user The user to check the referrer status for
    /// @return The referrer status of the user for the given key
    function getReferrerStatus(bytes calldata key, address user) external view returns (ReferralStatus) {
        return refererStatus[key][user];
    }

    /// @notice Gets the referrer for a specific user and referral key
    /// @param key The referral key to check
    /// @param user The user to check the referrer for
    /// @return The referrer of the user for the given key
    function getReferrer(bytes calldata key, address user) external view returns (address) {
        return keyToUserToReferrer[key][user];
    }

    /// @notice Gets the cost of a referral for a specific key
    /// @param key The referral key to check
    /// @return The cost of the referral for the given key
    function getCostOfReferral(bytes calldata key) external view returns (uint256) {
        return referralPrograms[key].cost;
    }

    /// @notice Gets the payment token of a referral program
    /// @param key The referral key to check
    /// @return The payment token of the referral program
    function getPaymentToken(bytes calldata key) external view returns (address) {
        return referralPrograms[key].paymentToken;
    }

    /// @notice Checks if a referral program requires authorization
    /// @param key The referral key to check
    /// @return True if the referral program requires authorization, false otherwise
    function requiresAuthorization(bytes calldata key) external view returns (bool) {
        return referralPrograms[key].requiresAuthorization;
    }

    /// @notice Checks if a referral program requires a referrer to be set
    /// @param key The referral key to check
    /// @return True if the referral program requires a referrer to be set, false otherwise
    function requiresRefererToBeSet(bytes calldata key) external view returns (bool) {
        return referralPrograms[key].requiresRefererToBeSet;
    }
}
