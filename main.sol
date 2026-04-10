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
    error HfcSaloonUnknown(uint256 id);
    error HfcSaloonSealed(uint256 id);
    error HfcCouchOverflow(uint256 cap, uint256 next);
    error HfcCouchVacant();
    error HfcAlreadySeated();
    error HfcChorusTooWide(uint256 have, uint256 cap);
    error HfcSlugAwkward(uint256 have, uint256 cap);
    error HfcSigilZero();
    error HfcTipTooThin(uint256 got, uint256 need);
    error HfcBarrelEmpty();
    error HfcBarrelShort(uint256 have, uint256 ask);
    error HfcBarrelCeiling(uint96 next, uint96 cap);
    error HfcShoutCooldown(uint64 readyAt);
    error HfcGlobally86d(address who);
    error HfcClipOn(address who, uint256 saloon);
    error HfcHostOnly();
    error HfcCaptainOrCurator();
    error HfcKittyDry();
    error HfcForwardFail(address to, uint256 wei_);
    error HfcReverbTrap();
    error HfcInviteStale(uint64 expiresAt);
    error HfcInviteMismatch(address expect, address got);
    error HfcPartyFull(uint256 cap);
    error HfcPartyUnknown(uint256 pid);
    error HfcRankOutOfBand(uint8 r);
    error HfcVibeOutOfBand(uint8 v);
    error HfcCapOutOfBand(uint32 c);
    error HfcSaloonLimit(uint256 have, uint256 max_);
    error HfcWhisperUnknown(uint256 wid);
    error HfcSelfPing();
    error HfcDuplicateSlug(bytes32 slug);
    error HfcWatchlistClash(address a, address b);
    error HfcLedgerSkew(uint256 bal, uint256 barrels, uint256 kitty);
    error HfcEmoteSpam(uint64 readyAt);
    error HfcReactionCap(uint8 lane);
    error HfcDuelSelf();
    error HfcSpotlightUnknown(uint256 sid);
    error HfcBountyThin(uint256 got, uint256 need);
    error HfcBountyStillLocked(uint64 unlockAt);
    error HfcBountyVaultEmpty();

    event SaloonSpawned(
        uint256 indexed saloonId,
        address indexed host,
        bytes32 slug,
        uint32 couchCap,
        uint8 vibe,
        uint64 whenTs
    );
    event SaloonSealed(uint256 indexed saloonId, address indexed by);
    event CouchClaimed(uint256 indexed saloonId, address indexed guest, uint8 guildRank, uint64 whenTs);
    event CouchVacated(uint256 indexed saloonId, address indexed guest, uint64 whenTs);
    event ChorusPosted(
        uint256 indexed whisperId,
        uint256 indexed saloonId,
        address indexed bard,
        bytes32 sigil,
        uint8 tintBand,
        uint64 whenTs
    );
    event NickTagged(address indexed who, bytes32 nickDigest);
    event TipSplashed(uint256 indexed saloonId, address indexed from, uint256 weiAmt, uint64 whenTs);
    event BarrelWithdrawn(uint256 indexed saloonId, address indexed host, uint256 weiAmt, uint64 whenTs);
    event GuildKittyFed(address indexed from, uint256 weiAmt, uint64 whenTs);
    event GuildKittySwept(address indexed to, uint256 weiAmt, uint64 whenTs);
    event ClipToggled(uint256 indexed saloonId, address indexed target, bool clipped, address indexed by);
    event BanHammer(address indexed target, bool banned, address indexed by);
    event WatchCaptainRotated(address indexed prior, address indexed next, address indexed by);
    event GuildVaultRotated(address indexed prior, address indexed next, address indexed by);
    event PartyFounded(uint256 indexed partyId, address indexed leader, uint32 cap, uint64 whenTs);
    event PartyJoined(uint256 indexed partyId, address indexed who, uint64 whenTs);
    event PartyLeft(uint256 indexed partyId, address indexed who, uint64 whenTs);
    event PartyDisbanded(uint256 indexed partyId, address indexed by, uint64 whenTs);
    event InviteMinted(bytes32 indexed inviteHash, uint256 indexed saloonId, address indexed guest, uint64 expiresAt);
    event LobbyFlagSet(uint256 indexed saloonId, uint8 prior, uint8 next, address indexed by);
    event PingEcho(address indexed from, address indexed to, bytes32 nonce, uint64 whenTs);
    event EmoteSpark(
        uint256 indexed saloonId,
