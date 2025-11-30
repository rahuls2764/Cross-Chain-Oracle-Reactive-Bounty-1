// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./IAggregatorV3.sol";

library ChainlinkDataReader {
    struct PriceData {
        uint80 roundId;
        int256 answer;
        uint256 startedAt;
        uint256 updatedAt;
        uint80 answeredInRound;
        uint8 decimals;
        string description;
    }

    error StalePrice(uint256 updatedAt, uint256 threshold);
    error InvalidPrice(int256 answer);
    error InvalidRound(uint80 roundId);

    function readLatest(address aggregator) internal view returns (PriceData memory data) {
        IAggregatorV3 feed = IAggregatorV3(aggregator);
        
        (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();

        if (answer <= 0) revert InvalidPrice(answer);
        if (roundId == 0) revert InvalidRound(roundId);

        data = PriceData({
            roundId: roundId,
            answer: answer,
            startedAt: startedAt,
            updatedAt: updatedAt,
            answeredInRound: answeredInRound,
            decimals: feed.decimals(),
            description: feed.description()
        });
    }

    function readLatestWithStalenessCheck(address aggregator, uint256 stalenessThreshold) 
        internal 
        view 
        returns (PriceData memory data) 
    {
        data = readLatest(aggregator);
        
        if (block.timestamp - data.updatedAt > stalenessThreshold) {
            revert StalePrice(data.updatedAt, stalenessThreshold);
        }
    }

    function readRound(address aggregator, uint80 roundId) 
        internal 
        view 
        returns (PriceData memory data) 
    {
        IAggregatorV3 feed = IAggregatorV3(aggregator);
        
        (
            uint80 rId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = feed.getRoundData(roundId);

        if (answer <= 0) revert InvalidPrice(answer);

        data = PriceData({
            roundId: rId,
            answer: answer,
            startedAt: startedAt,
            updatedAt: updatedAt,
            answeredInRound: answeredInRound,
            decimals: feed.decimals(),
            description: feed.description()
        });
    }
}