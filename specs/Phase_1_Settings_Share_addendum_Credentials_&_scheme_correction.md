Review: Phase 1 Settings & Share — Addendum (credentials + scheme correction)
Outcome: One required fix still open (carried from last review). Two minor notes.

Security check — clean
No client_secret, appSecret, or equivalent found anywhere in lib/. Both identifiers (_odClientId, _dbAppKey) are public client identifiers used in PKCE flows that require no secret — safe to commit. ✅

Credentials — correct
Constant	Value	Status
_odClientId	85bd1269-8a45-47a1-93e5-6394edf7fd6b	Valid Azure client ID UUID ✅
_odRedirectUrl	lookwhostalking://auth	Valid URI scheme ✅
_dbAppKey	ypxmmh1ye0mzpby	Valid Dropbox app key ✅
_dbRedirectUrl	db-ypxmmh1ye0mzpby://2/token	Correct Dropbox pattern ✅
Manifest OneDrive scheme	lookwhostalking	Matches redirect URL ✅
Manifest Dropbox scheme	db-ypxmmh1ye0mzpby	Matches redirect URL ✅
The msauth.… → lookwhostalking scheme correction is valid — Azure rejected the original because URI schemes cannot contain underscores (RFC 3986).

Required fix — _odGraphBase missing / (still not fixed)
This was the only required change from last review and it was not addressed. onedrive_provider.dart:22:


// STILL WRONG:
'https://graph.microsoft.com/v1.0/me/drive/special/approot:$_odAppFolder';

// REQUIRED:
'https://graph.microsoft.com/v1.0/me/drive/special/approot:/$_odAppFolder';
Graph API path-based addressing requires approot:/{relative-path}. Without the leading /, every upload session, list, download, and delete will return a 400 or 404 on a real device. One character.

Minor notes (not blockers, no change required before commit)
1. Stale manifest comment — AndroidManifest.xml:33-35 still says "msauth scheme, package based" and "Placeholders must be replaced". Both are now wrong. Worth cleaning up in this commit or the next.

2. Scheme hijack risk — lookwhostalking://auth is a short, generic custom scheme. Any other Android app could register the same scheme and intercept the OAuth redirect. com.lookwhostalking://auth (reverse-DNS, no underscores) would be collision-resistant. Not urgent — Azure would need another redirect URI update — but worth doing before public release.

Fix the one-character _odGraphBase issue, then this pass is ready to commit.
