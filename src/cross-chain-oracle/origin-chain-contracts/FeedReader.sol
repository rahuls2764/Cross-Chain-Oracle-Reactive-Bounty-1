// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./FeedRegistry.sol";
import "./ChainlinkDataReader.sol";
import "./CrossChainMessage.sol";
import "lib/reactive-lib/src/abstract-base/AbstractCallback.sol";

interface AggregatorV3Interface {
    function latestRoundData() external view returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
    function decimals() external view returns (uint8);
    function description() external view returns (string memory);
}

contract FeedReader is AbstractCallback {
    using FeedRegistry for FeedRegistry.Registry;
    using ChainlinkDataReader for address;
    using CrossChainMessage for CrossChainMessage.FeedMessage;

    FeedRegistry.Registry private registry;
    
    address public owner;
    bytes32 public immutable DOMAIN_SEPARATOR;
    uint256 public stalenessThreshold;

    event CrossChainMessageReady(
        bytes32 indexed feedId,
        address indexed aggregator,
        uint64 destinationChainId,
        address destinationFeed,
        uint8 decimals,
        string description,
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound,
        uint256 timestamp
    );

    modifier onlyOwner() {
        require(msg.sender == owner, "Unauthorized");
        _;
    }

    constructor(address _callback_sender, uint256 _stalenessThreshold) AbstractCallback(_callback_sender) payable {
        owner = msg.sender;
        stalenessThreshold = _stalenessThreshold;
        
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("FeedReader")),
                keccak256(bytes("1.0.0")),
                block.chainid,
                address(this)
            )
        );
    }

    function registerFeed(
        address aggregator,
        uint64 destinationChainId,
        address destinationFeed,
        string calldata identifier
    ) external onlyOwner returns (bytes32) {
        return registry.register(aggregator, destinationChainId, destinationFeed, identifier);
    }

    function setFeedActive(bytes32 feedId, bool active) external onlyOwner {
        registry.setActive(feedId, active);
    }

    function setStalenessThreshold(uint256 _threshold) external onlyOwner {
        stalenessThreshold = _threshold;
    }

    function readAndEmit(bytes32 feedId) external {
        FeedRegistry.Feed memory feed = registry.get(feedId);
        require(feed.active, "Feed inactive");

        ChainlinkDataReader.PriceData memory priceData = 
            stalenessThreshold > 0 
                ? feed.aggregator.readLatestWithStalenessCheck(stalenessThreshold)
                : feed.aggregator.readLatest();

        _emitMessage(feedId, feed, priceData);
    }

    function readAndEmitAll(address /*spender*/) external {
        bytes32[] memory feedIds = registry.getActiveFeedIds();
        for (uint256 i = 0; i < feedIds.length; i++) {
            FeedRegistry.Feed memory feed = registry.get(feedIds[i]);

            try AggregatorV3Interface(feed.aggregator).latestRoundData() returns (
                uint80 roundId,
                int256 answer,
                uint256 startedAt,
                uint256 updatedAt,
                uint80 answeredInRound
            ) {
                // gather decimals and description from the external aggregator
                uint8 decimals = AggregatorV3Interface(feed.aggregator).decimals();
                string memory description = AggregatorV3Interface(feed.aggregator).description();

                ChainlinkDataReader.PriceData memory priceData = ChainlinkDataReader.PriceData({
                    decimals: decimals,
                    description: description,
                    roundId: roundId,
                    answer: answer,
                    startedAt: startedAt,
                    updatedAt: updatedAt,
                    answeredInRound: answeredInRound
                });

                _emitMessage(feedIds[i], feed, priceData);
            } catch {
                continue;
            }
        }
    }

    function _emitMessage(
        bytes32 feedId,
        FeedRegistry.Feed memory feed,
        ChainlinkDataReader.PriceData memory priceData
    ) private {
        emit CrossChainMessageReady(
            feedId,
            feed.aggregator,
            feed.destinationChainId,
            feed.destinationFeed,
            priceData.decimals,
            priceData.description,
            priceData.roundId,
            priceData.answer,
            priceData.startedAt,
            priceData.updatedAt,
            priceData.answeredInRound,
            block.timestamp
        );
    }

    function getFeed(bytes32 feedId) external view returns (FeedRegistry.Feed memory) {
        return registry.get(feedId);
    }

    function getAllFeeds() external view returns (bytes32[] memory) {
        return registry.getAllFeedIds();
    }

    function getActiveFeeds() external view returns (bytes32[] memory) {
        return registry.getActiveFeedIds();
    }

    function getFeedsByAggregator(address aggregator) external view returns (bytes32[] memory) {
        return registry.getFeedsByAggregator(aggregator);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Invalid address");
        owner = newOwner;
    }
}