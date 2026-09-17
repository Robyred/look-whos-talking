# SSH Keys and GitHub Keys — What They Are and How to Set Them Up

A practical guide for connecting to GitHub without typing a password, and for
cloning a *private* repository on a new machine.

---

## 1. The problem this solves

When you `git clone` a repository over HTTPS, Git asks for a username and
password. GitHub removed password authentication for Git operations in 2021, so
that no longer works. You now have two options:

| Method | What you use instead of a password |
|---|---|
| **SSH** | A **key pair** stored on your machine |
| **HTTPS** | A **Personal Access Token (PAT)** — a long random string |

SSH is the better default: it's set up once, then it works silently forever. A
PAT is a password substitute you have to paste and that expires.

The rest of this document covers SSH first, then PATs.

---

## 2. What an SSH key actually is

SSH (**Secure Shell**) is a protocol for connecting to another computer securely.
GitHub uses it so your machine can prove *"I am Jack's computer"* without sending
a password over the network.

An SSH key is really a **key pair** — two mathematically linked files:

| File | Name | Analogy | Where it lives |
|---|---|---|---|
| `id_ed25519` | **private key** | Your house key | Stays on your machine. **Never share it.** |
| `id_ed25519.pub` | **public key** | The lock on the door | You give copies to GitHub |

**The crucial idea:** you put the **public** key on GitHub, and keep the
**private** key on your computer. It feels backwards at first — the thing you
upload is the lock, not the key.

When you connect, GitHub says *"prove you hold the private key matching this
public key."* Your machine answers with a mathematical proof. GitHub verifies it
— and at no point does your private key leave your computer.

### Why is it safe to share the public key?

Because the relationship is **one-way**. From the public key you cannot work
backwards to the private key. This is why you can paste your `.pub` file into a
public website, or email it, with no risk.

The reverse is emphatically not true: anyone who obtains your **private** key
can impersonate you on every service that trusts it.

---

## 3. Check whether you already have a key

Before creating anything, check:

```bash
ls -la ~/.ssh
```

Look for files named `id_ed25519` / `id_ed25519.pub` or `id_rsa` / `id_rsa.pub`.

- **You have a `.pub` file** → skip to step 5 (add it to GitHub).
- **Nothing there** → continue with step 4.

---

## 4. Generate a key pair

```bash
ssh-keygen -t ed25519 -C "jackcummins@hotmail.com"
```

What each part means:

- `-t ed25519` — the key **type**. Ed25519 is the modern, recommended algorithm:
  shorter and stronger than the older RSA. This is what GitHub's own docs use.
- `-C "..."` — a **comment**, just a label so you can identify the key later.
  Your email is conventional. Use the email on your GitHub account.
- `ssh-keygen` — the program that generates the pair.

You'll see three prompts:

```
Enter file in which to save the key (/home/jack/.ssh/id_ed25519):      ← press Enter
Enter passphrase (empty for no passphrase):                             ← see below
Enter same passphrase again:
```

**About the passphrase.** It encrypts the private key on disk. If someone steals
your laptop and your key has no passphrase, they can push to your repos. With a
passphrase, they'd need to crack that too. **Use one.** You will not have to type
it constantly — the ssh-agent (step 6) remembers it.

> If you're on a legacy system that doesn't support Ed25519, use
> `ssh-keygen -t rsa -b 4096 -C "your_email@example.com"` instead.

---

## 5. Add the public key to GitHub

**Copy the public key to your clipboard:**

```bash
cat ~/.ssh/id_ed25519.pub
```

Note the `.pub` suffix — that's the whole point. Select the entire output,
starting with `ssh-ed25519` and ending with your comment.

> ⚠️ **Do not use `id_ed25519` without `.pub`.** That is your private key. Never
> paste it anywhere.

**Paste it into GitHub:**

1. Go to <https://github.com/settings/keys>
2. Click **New SSH key**
3. **Title** — name it after the machine, e.g. `Jack's Linux laptop`
4. **Key type** — leave as *Authentication Key*
5. **Key** — paste the whole line
6. Click **Add SSH key**

The title matters more than it seems: when you have several machines, it's how
you revoke one specific machine's access without affecting the others.

---

## 6. Make it painless: the ssh-agent

The **ssh-agent** is a background program that holds your decrypted private key
in memory, so you type your passphrase once per session rather than on every
Git operation.

**Start the agent and add your key:**

```bash
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519
```

**To avoid repeating that in every new terminal**, create `~/.ssh/config`:

```bash
nano ~/.ssh/config
```

Add:

```
Host github.com
  AddKeysToAgent yes
  IdentityFile ~/.ssh/id_ed25519
```

Then lock the file down:

```bash
chmod 600 ~/.ssh/config
```

`AddKeysToAgent yes` tells SSH to hand the key to the agent automatically the
first time it's used, so the commands above become unnecessary.

> **macOS only:** add `UseKeychain yes` under the `Host github.com` block, and
> use `ssh-add --apple-use-keychain ~/.ssh/id_ed25519`. That stores the
> passphrase in your macOS Keychain. On Linux, omit `UseKeychain` — it's an
> Apple-specific option and Linux SSH will reject it as a bad configuration.

---

## 7. Test the connection

```bash
ssh -T git@github.com
```

**Success looks like:**

```
Hi Robyred! You've successfully authenticated, but GitHub does not provide shell access.
```

That message is exactly what you want. The "does not provide shell access" part
is normal — GitHub only allows Git operations, not an interactive login.

**First-time prompt:** you'll be asked whether to trust `github.com`:

```
The authenticity of host 'github.com (140.82.121.4)' can't be established.
ED25519 key fingerprint is SHA256:+DiY3wvvV6TuJJhbpZisF/zLDA0zPMSvHdkr4UvCOqU.
Are you sure you want to continue connecting (yes/no/[fingerprint])?
```

Type `yes`. Verify the fingerprint matches GitHub's published one if you want to
be careful — it's listed at <https://docs.github.com/en/authentication/troubleshooting-ssh/error-host-key-verification-failed>.

---

## 8. Point an existing repository at SSH

If you cloned over HTTPS, the remote still uses HTTPS. Check it:

```bash
git remote -v
```

If it shows `https://github.com/Robyred/look-whos-talking.git`, switch it:

```bash
git remote set-url origin git@github.com:Robyred/look-whos-talking.git
```

Verify:

```bash
git remote -v      # should now start with git@github.com:
git fetch          # should complete with no password prompt
```

---

## 9. The alternative: a Personal Access Token (PAT)

A **PAT** is a long random string that acts as your password for HTTPS Git
operations. You asked about "GitHub keys" — this is the *other* thing people mean
by that.

**When to use a PAT instead of SSH:**

- You're on a machine where you can't create SSH keys (locked-down work machine)
- You need fine-grained, expiring access for a script or CI job
- You're using an HTTPS-only tool

**Create one:**

1. Go to <https://github.com/settings/tokens?type=beta> (fine-grained tokens)
2. **Generate new token**
3. Set an **expiry** (90 days is sensible)
4. Under **Repository access**, choose *Only select repositories* → pick your repo
5. Under **Permissions** → *Repository permissions* → set **Contents: Read and write**
6. Generate, then **copy the token immediately** — GitHub shows it once, never again

**Use it:** when Git prompts for a password, paste the token. For a username, put
anything (or your GitHub username).

**Store it** so you're not pasting constantly:

```bash
git config --global credential.helper store
```

> ⚠️ `store` writes the token to `~/.git-credentials` in **plain text**. On a
> shared machine, use `git config --global credential.helper libsecret` instead.

**Fine-grained vs classic tokens:** prefer fine-grained. A classic token with the
`repo` scope grants access to *all* your repositories; fine-grained tokens can be
limited to one repo and to specific permissions.

---

## 10. SSH vs PAT — which should you use?

| | SSH key | Personal Access Token |
|---|---|---|
| Setup effort | Once, ~5 minutes | Per token, and tokens expire |
| Expiry | Never (until you revoke) | Typically 30–90 days |
| Best for | Daily development on your own machines | Scripts, CI, locked-down machines |
| Revoke one machine only | Yes, per key | Yes, per token |
| Typing required | No (with ssh-agent) | Pasting, unless you store it |

**For your case — moving to a second computer, cloning a private repo — use SSH.**

---

## 11. Security rules worth internalising

1. **The private key never leaves your machine.** No exceptions. Not to GitHub,
   not to a support person, not into a chat window.
2. **Only `.pub` files get shared.** If a file doesn't end in `.pub`, don't paste it.
3. **Permissions matter.** SSH refuses to use keys that are readable by others:
   ```bash
   chmod 700 ~/.ssh
   chmod 600 ~/.ssh/id_ed25519
   chmod 644 ~/.ssh/id_ed25519.pub
   ```
4. **Use a passphrase.** The agent removes the inconvenience, so there's no real
   reason not to.
5. **One key per machine.** If a laptop is lost or sold, revoke just that key at
   <https://github.com/settings/keys> rather than rotating everything.

---

## 12. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `Permission denied (publickey)` | Key not added to GitHub, or agent doesn't hold it | `ssh-add ~/.ssh/id_ed25519`, then `ssh -T git@github.com` |
| `Permission denied (publickey)` after adding | Wrong key uploaded — you pasted the private key | Re-upload the `.pub` file contents |
| `Could not open a connection to your authentication agent` | Agent isn't running in this shell | `eval "$(ssh-agent -s)"` |
| Asked for passphrase every time | `AddKeysToAgent` not set | Add it to `~/.ssh/config` (step 6) |
| `Bad configuration option: usekeychain` | `UseKeychain` used on Linux | Remove that line — it's macOS-only |
| `Host key verification failed` | GitHub's host key changed or is unknown | Remove the stale entry: `ssh-keygen -R github.com` |
| `ERROR: Repository not found` | Private repo, and authenticated as an account without access | Check `ssh -T git@github.com` names the right user |
| Still prompted for a password | Remote is still HTTPS | `git remote set-url origin git@github.com:USER/REPO.git` |
| `remote origin already exists` | Setting a remote twice | Use `git remote set-url`, not `git remote add` |

---

## 13. Quick reference

```bash
# Generate
ssh-keygen -t ed25519 -C "jackcummins@hotmail.com"

# Start agent and load key
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519

# Show the PUBLIC key to paste into GitHub
cat ~/.ssh/id_ed25519.pub

# Test
ssh -T git@github.com

# Switch an existing clone to SSH
git remote set-url origin git@github.com:Robyred/look-whos-talking.git

# Fix permissions
chmod 700 ~/.ssh && chmod 600 ~/.ssh/id_ed25519 ~/.ssh/config && chmod 644 ~/.ssh/id_ed25519.pub
```

---

## 14. Applying this to the new computer

Before you travel:

1. Generate the key on the **new** machine, not this one — one key per machine.
2. Add its `.pub` to <https://github.com/settings/keys> with a recognisable title.
3. Test with `ssh -T git@github.com` before you need it.
4. Then `git clone git@github.com:Robyred/look-whos-talking.git` will just work,
   and a private repository needs no extra steps.

If you'd rather not set up SSH on the new machine, fall back to a fine-grained
PAT (step 9) — but you'll be pasting it into a prompt instead.

See `README.md` for what to do *after* the clone — the virtualenv and
HuggingFace token are not in the repository.
