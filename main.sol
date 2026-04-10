// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * Pixel pit-stop ledger — quarter stacks, couch co-op pings, and neon banter hashes.
 * Saloon barrels stay escrowed until hosts draw; the guild kitty is the only sweep lane
 * for the sovereign. Off-chain clients render chorus text; here we keep sigils and seats.
 */

library HfcBitfield {
    uint8 internal constant LOCK_LOBBY = 0x01;
    uint8 internal constant DIM_LIGHTS = 0x02;
    uint8 internal constant VIP_ROPE = 0x04;
    uint8 internal constant AFK_BEACON = 0x08;

    function has(uint8 mask, uint8 flag) internal pure returns (bool) {
        return (mask & flag) != 0;
    }

    function flip(uint8 mask, uint8 flag) internal pure returns (uint8) {
        return mask ^ flag;
    }

    function with(uint8 mask, uint8 flag) internal pure returns (uint8) {
        return mask | flag;
    }

    function without(uint8 mask, uint8 flag) internal pure returns (uint8) {
        return mask & ~flag;
    }

    function onlyFlags(uint8 mask, uint8 allowed) internal pure returns (bool) {
        return (mask | allowed) == allowed;
    }
}

library HfcDice {
    function rollMix(bytes32 salt, address who, uint256 blk, uint256 nonce) internal view returns (uint256) {
        return uint256(keccak256(abi.encodePacked(salt, who, blk, nonce, address(this))));
    }

    function band4(uint256 mix) internal pure returns (uint8) {
        return uint8(mix % 4);
    }

    function band16(uint256 mix) internal pure returns (uint8) {
        return uint8(mix % 16);
    }

    function band64(uint256 mix) internal pure returns (uint8) {
        return uint8(mix % 64);
    }

    function auraTint(uint256 mix) internal pure returns (uint24 rgb) {
        rgb = uint24(mix & 0xFFFFFF);
    }

    function streakGate(uint256 mix, uint8 need) internal pure returns (bool) {
        return uint8(mix % 100) < need;
    }
}

library HfcTxt {
    uint256 internal constant MAX_CHORUS = 360;
    uint256 internal constant MAX_SLUG_LEN = 48;
    uint256 internal constant MAX_EMOTE_KEY = 24;

    function lenOk(string calldata s, uint256 cap) internal pure returns (bool) {
        return bytes(s).length <= cap;
    }

    function lenOf(string memory s) internal pure returns (uint256) {
        return bytes(s).length;
    }
}

contract HellFireClub {
    error HfcGateDenied();
