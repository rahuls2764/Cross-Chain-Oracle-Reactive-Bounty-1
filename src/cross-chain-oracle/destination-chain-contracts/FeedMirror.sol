// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../origin-chain-contracts/IAggregatorV3.sol";
import "./PriceFeedStorage.sol";
import "./FeedMetadata.sol";
import "./AccessControl.sol";
import "lib/reactive-lib/src/abstract-base/AbstractCallback.sol";

contract FeedMirror is IAggregatorV3, AbstractCallback {
    using PriceFeedStorage for PriceFeedStorage.Feed;
    using FeedMetadata for FeedMetadata.Metadata;
    using AccessControl for AccessControl.Roles;

    PriceFeedStorage.Feed private feed;
    FeedMetadata.Metadata private metadata;
    AccessControl.Roles private roles;

    bytes32 public immutable DOMAIN_SEPARATOR;
    uint256 public constant version = 1;

    event PriceUpdated(
        uint80 indexed roundId,
        int256 answer,
        uint256 updatedAt,
        address indexed updater
    );

    event MetadataInitialized(
        address indexed sourceAggregator,
        uint64 sourceChainId,
        uint8 decimals,
        string description
    );

    modifier onlyOwner() {
        roles.requireOwner(msg.sender);
        _;
    }

    constructor(address _callback_sender) AbstractCallback(_callback_sender) {
        roles.initialize(msg.sender);
        
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("FeedMirror")),
                keccak256(bytes("1.0.0")),
                block.chainid,
                address(this)
            )
        );
    }

    function initialize(
        address sourceAggregator,
        uint64 sourceChainId,
        uint8 _decimals,
        string calldata _description
    ) external onlyOwner {
        metadata.initialize(sourceAggregator, sourceChainId, _decimals, _description);
        emit MetadataInitialized(sourceAggregator, sourceChainId, _decimals, _description);
    }

    function updatePrice(
        address /*spender*/,
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) external{
        metadata.requireInitialized();
        feed.updateRound(roundId, answer, startedAt, updatedAt, answeredInRound);
        emit PriceUpdated(roundId, answer, updatedAt, msg.sender);
    }

    function updatePriceBatch(
        uint80[] calldata roundIds,
        int256[] calldata answers,
        uint256[] calldata startedAts,
        uint256[] calldata updatedAts,
        uint80[] calldata answeredInRounds
    ) external{
        require(
            roundIds.length == answers.length &&
            roundIds.length == startedAts.length &&
            roundIds.length == updatedAts.length &&
            roundIds.length == answeredInRounds.length,
            "Length mismatch"
        );

        metadata.requireInitialized();

        for (uint256 i = 0; i < roundIds.length; i++) {
            feed.updateRound(
                roundIds[i],
                answers[i],
                startedAts[i],
                updatedAts[i],
                answeredInRounds[i]
            );
            emit PriceUpdated(roundIds[i], answers[i], updatedAts[i], msg.sender);
        }
    }

    function decimals() external view override returns (uint8) {
        return metadata.getDecimals();
    }

    function description() external view override returns (string memory) {
        return metadata.getDescription();
    }

    function latestRoundData()
        external
        view
        override
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return feed.getLatest();
    }

    function getRoundData(uint80 _roundId)
        external
        view
        override
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return feed.getRound(_roundId);
    }

    function getSourceInfo() external view returns (address aggregator, uint64 chainId) {
        return metadata.getSourceInfo();
    }

    function hasData() external view returns (bool) {
        return feed.hasData();
    }

    function getDataAge() external view returns (uint256) {
        return feed.getDataAge();
    }

    function getTotalRounds() external view returns (uint256) {
        return feed.getTotalRounds();
    }

    function getAllRoundIds() external view returns (uint80[] memory) {
        return feed.getAllRoundIds();
    }

    function transferOwnership(address newOwner) external onlyOwner {
        roles.transferOwnership(newOwner);
    }

    function emergencyUpdate(
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) external onlyOwner {
        metadata.requireInitialized();
        feed.updateRound(roundId, answer, startedAt, updatedAt, answeredInRound);
        emit PriceUpdated(roundId, answer, updatedAt, msg.sender);
    }
}