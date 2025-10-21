// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "@fhenixprotocol/cofhe-contracts/FHE.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract HackThePool is Ownable {
    euint8 public ZERO;

    uint256 gameId;

    struct GameStruct {
        euint64 encPool;
        uint64 resultPool;
        Guess[5] guesses;
        uint8 numGuesses;
        address winner;
        euint8 winnerIdx;
        bool claimed;
    }

    struct Guess {
        address player;
        euint64 guess;
        euint64 guessDif;
    }

    error NoGuessFound();
    error DecryptionNotReady(address player, uint256 gameId);
    error GameAlreadyFinished(uint256 gameId);

    // gameid-> GameStruct
    mapping(uint256 => GameStruct) gameState;

    //TODO: map player to gameid[]

    constructor() Ownable(msg.sender) {
        ZERO = FHE.asEuint8(0);
        FHE.allowThis(ZERO);
    }

    function guess(
        InEuint64 memory inTokenDeposit,
        InEuint64 memory inGuessAmount
    ) public {
        //TODO: tokenDeposit to real FHERC20 TransferFrom
        euint64 tokenDeposit = FHE.asEuint64(inTokenDeposit);
        euint64 guessAmount = FHE.asEuint64(inGuessAmount);

        gameState[gameId].encPool = FHE.add(
            gameState[gameId].encPool,
            tokenDeposit
        );

        uint8 guessIdx = gameState[gameId].numGuesses;

        gameState[gameId].guesses[guessIdx] = Guess({
            player: msg.sender,
            guess: guessAmount,
            guessDif: FHE.asEuint64(ZERO)
        });

        if (gameState[gameId].numGuesses < 4) {
            gameState[gameId].numGuesses++;
        } else {
            _finalizeGame();
            gameId++;
        }

        FHE.allowThis(gameState[gameId].encPool);
        FHE.allowThis(gameState[gameId].winnerIdx);
        FHE.allowThis(gameState[gameId].guesses[guessIdx].guess);
        FHE.allowThis(gameState[gameId].guesses[guessIdx].guessDif);

        FHE.allowSender(gameState[gameId].guesses[guessIdx].guess);
    }

    function removeGuess() public {
        require(gameState[gameId].numGuesses > 0, "No guesses to remove");

        // Find the player's guess
        uint8 playerGuessIdx = type(uint8).max;
        for (uint8 i = 0; i < gameState[gameId].numGuesses; i++) {
            if (gameState[gameId].guesses[i].player == msg.sender) {
                playerGuessIdx = i;
                break;
            }
        }

        if (playerGuessIdx == type(uint8).max) {
            revert NoGuessFound();
        }

        gameState[gameId].encPool = FHE.sub(
            gameState[gameId].encPool,
            gameState[gameId].guesses[playerGuessIdx].guess
        );
        // TODO: Transfer back from the contract to the sender

        // Remove the guess by shifting remaining guesses left
        for (
            uint8 i = playerGuessIdx;
            i < gameState[gameId].numGuesses - 1;
            i++
        ) {
            gameState[gameId].guesses[i] = gameState[gameId].guesses[i + 1];
        }

        // Clear the last slot and decrement count
        delete gameState[gameId].guesses[gameState[gameId].numGuesses - 1];
        gameState[gameId].numGuesses--;

        FHE.allowThis(gameState[gameId].encPool);
    }

    function claimPool(uint256 gameId) public {
        if (gameState[gameId].claimed) {
            revert GameAlreadyFinished(gameId);
        }
        (uint8 winnerIdx, bool decrypted) = FHE.getDecryptResultSafe(
            gameState[gameId].winnerIdx
        );

        if (!decrypted) {
            revert DecryptionNotReady(msg.sender, gameId);
        }

        gameState[gameId].winner = gameState[gameId].guesses[winnerIdx].player;
        //TODO: transfer from contracto to the winner
    }

    function _finalizeGame() private {
        require(gameState[gameId].numGuesses == 4, "not enough guesses");

        // Calculate differences for all guesses
        for (uint8 i = 0; i < 5; i++) {
            gameState[gameId].guesses[i].guessDif = _calculateDifference(
                gameState[gameId].guesses[i].guess,
                gameState[gameId].encPool
            );
        }

        // Find minimum difference using cascading comparisons
        euint8 winnerIdx = ZERO;
        euint64 minDiff = gameState[gameId].guesses[0].guessDif;

        for (uint8 i = 1; i < 5; i++) {
            ebool isSmaller = FHE.lt(
                gameState[gameId].guesses[i].guessDif,
                minDiff
            );
            winnerIdx = FHE.select(isSmaller, FHE.asEuint8(i), winnerIdx);
            minDiff = FHE.select(
                isSmaller,
                gameState[gameId].guesses[i].guessDif,
                minDiff
            );
        }

        gameState[gameId].winnerIdx = winnerIdx;
        FHE.decrypt(gameState[gameId].winnerIdx);
    }

    function _calculateDifference(
        euint64 playerGuess,
        euint64 poolAmount
    ) private returns (euint64) {
        ebool isBigger = FHE.gt(playerGuess, poolAmount);
        euint64 guessDiff = FHE.select(
            isBigger,
            FHE.sub(playerGuess, poolAmount),
            FHE.sub(poolAmount, playerGuess)
        );
        return guessDiff;
    }
}
