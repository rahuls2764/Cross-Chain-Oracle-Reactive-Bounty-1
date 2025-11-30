// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library PriceFeedStorage {
    struct Round {
        uint80 roundId;
        int256 answer;
        uint256 startedAt;
        uint256 updatedAt;
        uint80 answeredInRound;
        bool exists;
    }

    struct Feed {
        Round latest;
        mapping(uint80 => Round) rounds;
        uint80[] roundIds;
        uint256 totalRounds;
    }

    error RoundNotIncreasing(uint80 current, uint80 provided);
    error InvalidAnswer(int256 answer);
    error RoundNotFound(uint80 roundId);

    function updateRound(
        Feed storage self,
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) internal {
        if (roundId <= self.latest.roundId) {
            revert RoundNotIncreasing(self.latest.roundId, roundId);
        }
        if (answer <= 0) {
            revert InvalidAnswer(answer);
        }

        Round memory round = Round({
            roundId: roundId,
            answer: answer,
            startedAt: startedAt,
            updatedAt: updatedAt,
            answeredInRound: answeredInRound,
            exists: true
        });

        self.latest = round;
        self.rounds[roundId] = round;
        self.roundIds.push(roundId);
        self.totalRounds++;
    }

    function getLatest(Feed storage self) 
        internal 
        view 
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) 
    {
        require(self.latest.exists, "No data");
        return (
            self.latest.roundId,
            self.latest.answer,
            self.latest.startedAt,
            self.latest.updatedAt,
            self.latest.answeredInRound
        );
    }

    function getRound(Feed storage self, uint80 roundId)
        internal
        view
        returns (
            uint80,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        Round memory round = self.rounds[roundId];
        if (!round.exists) revert RoundNotFound(roundId);
        
        return (
            round.roundId,
            round.answer,
            round.startedAt,
            round.updatedAt,
            round.answeredInRound
        );
    }

    function hasData(Feed storage self) internal view returns (bool) {
        return self.latest.exists;
    }

    function getDataAge(Feed storage self) internal view returns (uint256) {
        if (!self.latest.exists) return type(uint256).max;
        return block.timestamp - self.latest.updatedAt;
    }

    function getTotalRounds(Feed storage self) internal view returns (uint256) {
        return self.totalRounds;
    }

    function getAllRoundIds(Feed storage self) internal view returns (uint80[] memory) {
        return self.roundIds;
    }
}