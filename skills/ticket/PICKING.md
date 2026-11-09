# Picking a Jira ticket

Only when `/ticket` got no argument. `<key>` is the Jira project key; **Hotfix** and the type buckets are defined in `${CLAUDE_SKILL_DIR}/JIRA.md` › Terms.

## 1. List the current sprint

`searchJiraIssuesUsingJql`, `maxResults: 100`, `fields: ["summary","issuetype","priority","status","updated","labels"]`:

```
project = <key> AND sprint in openSprints() AND assignee = currentUser() AND resolution = Unresolved
```

Empty → drop `AND assignee = currentUser()`, print key and title of the whole sprint, and ask which one; wait for the answer. Sprint empty too → stop and ask for a ticket.

**Done when:** you hold your open sprint tickets, or Quinn named one from the whole sprint, or the stop is printed.

## 2. Rank

Sort by each rule in order; a later rule only breaks ties of the earlier ones.

1. **Hotfix** tickets first.
2. Jira priority, most urgent first (tie: lower `priority.id`).
3. Type bucket: bug > story > epic > task > spike > other.
4. Status category In Progress before To Do.
5. `updated`, newest first.
6. Lower key number.

Print the ranked list (key, title, the rule that placed it) and take the top row.

**Done when:** exactly one key is chosen and the list is printed.
