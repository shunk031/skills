# Why the placeholder rule has no behavior case

`SKILL.md` says eval prompts for a private skill must use placeholder values, because those prompts are committed. A case was written for it and then removed.

The rule that a case may only assert what its prompt asks for cut the case down to nothing. Its prompt asked what the prompts in `evals.json` should contain, so "requires placeholder values instead of the real internal ones" was in scope and "gives the reason that these prompts are committed" was not: the prompt asked for content, not rationale. That second assertion held one trial in three, which is what an unrequested justification looks like when the model answers the question it was actually given.

The assertion that remained in scope passed on both arms in every trial. The evaluated model reaches for `<project-name>`-style placeholders on its own, without the skill. That is a finished measurement rather than a broken case: on this point the skill changes nothing.

An earlier version of the assertion did separate the arms, at 3/3 with the skill against 0/3 without. It required "placeholder hosts, accounts, and endpoints", and the baseline lost by covering two of the three nouns rather than by using real values. Rewriting it to judge the substance removed that margin, which is the honest result — the margin was the wording.

The rule stays in `SKILL.md`. The model usually getting this right is not the same as the rule being unnecessary, and the private repository's `AGENTS.md` states it as a hard requirement where the consequence of missing it is a committed secret.

# Why `edit-skill-from-dotfiles-checkout` is two cases

It carried three assertions: route the edit to the skill repository, pick the public one of the two, and describe reaching the machine through merge and apply. Each held about two trials in three, against a baseline of zero.

A trial passes only when every assertion in it passes, and a case needs a majority of trials, so which trial each miss landed in decided the verdict. The case passed one run and failed the next with nothing changed.

Choosing between the two repositories is already measured by `classify-new-skill-visibility`, whose prompt asks that directly, so that assertion was dropped rather than moved. The other two became `edit-skill-from-dotfiles-checkout` and `skill-edit-reaches-the-machine`, one assertion each. Both now pass every trial against a baseline that does not.

# Why `live-skill-edit-does-not-stick` is not a trigger case

The prompt describes an edit to `~/.agents/skills/<name>/SKILL.md` that disappeared and asks what happened. It measures well as a behaviour case: with the skill the agent identifies the installed copy as CLI-managed, routes the source to the owning repository, and names the refresh command, against a baseline that does not.

As a trigger case it never settled. Across three runs the agent read the skill in one trial of three, every time.

Two changes were tried. The description gained an explicit clause for an edit that vanished, reverted, or did not take effect, in the prompt's own vocabulary. Then it was cut from 680 characters to 464 and that clause moved near the front, since a description is read to decide whether to open a skill and the deciding condition was buried at the end. Neither moved the number.

A separate defect was fixed in between, so this is not a misreading: the judge had been returning `declined` for a run whose evidence said the agent used the guidance, because the agent had not also used a different skill the body names ([shunk031/shuhari#87](https://github.com/shunk031/shuhari/pull/87)). After that landed, the failures are purely that the skill is not read.

The likely reason is the prompt itself. It asks what happened to a file, not for skill management, and investigating the filesystem first is the reasonable opening move. Writing more of the prompt into the description would make the case pass by copying the answer into the question, which measures the copying.

So the case stays in `evals.json`, where it holds, and is not a trigger case. The remaining trigger cases are three positive and three negative. If a future model reads the skill here, the case is recoverable from this repository's history.
