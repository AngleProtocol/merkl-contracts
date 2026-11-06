// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <=0.9.0;

/// @notice Minimal Safe v1.3.0 proxy factory interface used by deployment scripts.
interface IGnosisSafeProxyFactory {
    function createProxyWithNonce(address _singleton, bytes memory initializer, uint256 saltNonce) external returns (address proxy);
}

/// @notice Minimal Safe v1.3.0 interface used by deployment and verification scripts.
interface IGnosisSafe {
    function setup(
        address[] calldata _owners,
        uint256 _threshold,
        address to,
        bytes calldata data,
        address fallbackHandler,
        address paymentToken,
        uint256 payment,
        address payable paymentReceiver
    ) external;

    function getOwners() external view returns (address[] memory);
    function getThreshold() external view returns (uint256);
    function getModulesPaginated(address start, uint256 pageSize) external view returns (address[] memory array, address next);
    function nonce() external view returns (uint256);
    function VERSION() external view returns (string memory);
}
