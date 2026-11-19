#!/usr/bin/env bash
# Board operations on the project's GitHub board: every gh call the skills make on a ticket.
# Run from inside the project (project.sh, next to this script, names the wiki repo, owner and
# Project number). A ticket is an issue in the wiki repo; its number is its id.
#   tickets.sh list                      unblocked To do tickets, urgent first, then lowest number;
#                                        one per line: <number> TAB <labels, comma-joined> TAB <title>
#   tickets.sh show <n>                  one JSON object: number, title, body, state, status,
#                                        labels (names), comments ({author, body}),
#                                        blockers ({ref: owner/name#n, state})
#   tickets.sh status <n> <status>       todo | in-progress | done (any case, spaces or hyphens);
#                                        prints `<n>: <Status>`
#   tickets.sh create --title T [--body B] [--label a,b] [--blocked-by n,owner/name#n]
#                                        creates the issue, adds it to the Project, prints its number
#   tickets.sh close <n> --comment TEXT [--not-planned]
#                                        closes with the comment; --not-planned for a ticket with no code
# Item lists pass an explicit limit of 200 (gh's default is 30). Blocked-by goes through GraphQL.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
die() { echo "tickets.sh: $*" >&2; exit 1; }

lookup=$(bash "$here/project.sh")
field() { sed -n "s/^$1: //p" <<<"$lookup"; }
[ "$(field project)" != none ] || die "$(field reason)"
[ "$(field board)" = github ] || die "board is $(field board), not github"
REPO=$(field repo); OWNER=$(field owner); NUM=$(field number)
[ -n "$REPO" ] && [ -n "$OWNER" ] && [ -n "$NUM" ] || die "project.md needs repo, owner and project (number)"
WIKI_OWNER=${REPO%%/*}; WIKI_NAME=${REPO#*/}

items() { gh project item-list "$NUM" --owner "$OWNER" -L 200 --format json; }

# issue_id <owner/name> <n>: node id
issue_id() { gh issue view "$2" --repo "$1" --json id | jq -r .id; }

# blockers <n>: JSON array of {ref, state}
blockers() {
  gh api graphql -F owner="$WIKI_OWNER" -F name="$WIKI_NAME" -F number="$1" -f query='
query($owner:String!,$name:String!,$number:Int!){repository(owner:$owner,name:$name){issue(number:$number){blockedBy(first:50){nodes{number state repository{nameWithOwner}}}}}}' |
    jq -c '[.data.repository.issue.blockedBy.nodes[] | {ref: "\(.repository.nameWithOwner)#\(.number)", state}]'
}

cmd=${1:-}; [ $# -eq 0 ] || shift
case $cmd in
  list)
    items | jq -r '
      .items | map(select(.status == "Todo" and .content.type == "Issue"))
      | map({n: .content.number, t: .content.title, l: (.labels // [])})
      | sort_by([(if (.l | index("urgent")) then 0 else 1 end), .n])
      | .[] | "\(.n)\u001f\(.l | join(","))\u001f\(.t)"' |
    while IFS=$'\037' read -r n labels title; do
      [ "$(blockers "$n" | jq '[.[] | select(.state == "OPEN")] | length')" = 0 ] &&
        printf '%s\t%s\t%s\n' "$n" "$labels" "$title"
    done || true
    ;;
  show)
    n=${1:?ticket number}
    issue=$(gh issue view "$n" --repo "$REPO" --json number,title,body,labels,comments,state)
    status=$(items | jq -r --argjson n "$n" '[.items[] | select(.content.number == $n)][0].status // ""')
    jq --arg status "$status" --argjson blockers "$(blockers "$n")" '
      {number, title, body, state, status: $status,
       labels: [.labels[].name],
       comments: [.comments[] | {author: .author.login, body}],
       blockers: $blockers}' <<<"$issue"
    ;;
  status)
    n=${1:?ticket number}; want=${2:?status}
    case $(tr '[:upper:] _' '[:lower:]--' <<<"$want") in
      todo|to-do) name=Todo ;;
      in-progress) name="In Progress" ;;
      done) name=Done ;;
      *) die "unknown status $want (todo, in-progress, done)" ;;
    esac
    item=$(items | jq -r --argjson n "$n" '[.items[] | select(.content.number == $n)][0].id // empty')
    [ -n "$item" ] || die "ticket $n is not on the Project"
    project=$(gh project view "$NUM" --owner "$OWNER" --format json | jq -r .id)
    fields=$(gh project field-list "$NUM" --owner "$OWNER" -L 200 --format json)
    fid=$(jq -r '.fields[] | select(.name == "Status") | .id' <<<"$fields")
    oid=$(jq -r --arg o "$name" '.fields[] | select(.name == "Status") | .options[] | select(.name == $o) | .id' <<<"$fields")
    [ -n "$fid" ] && [ -n "$oid" ] || die "Project has no Status option $name"
    gh project item-edit --id "$item" --project-id "$project" --field-id "$fid" --single-select-option-id "$oid" >/dev/null
    echo "$n: $name"
    ;;
  create)
    title=; body=; labels=; blocked=
    while [ $# -gt 0 ]; do
      case $1 in
        --title) title=${2?}; shift 2 ;;
        --body) body=${2?}; shift 2 ;;
        --label) labels=${2?}; shift 2 ;;
        --blocked-by) blocked=${2?}; shift 2 ;;
        *) die "create: unknown argument $1" ;;
      esac
    done
    [ -n "$title" ] || die "create: --title is required"
    args=(--repo "$REPO" --title "$title" --body "$body")
    IFS=, read -ra ls <<<"$labels"
    for l in ${ls[@]+"${ls[@]}"}; do args+=(--label "$l"); done
    url=$(gh issue create "${args[@]}")
    n=${url##*/}
    gh project item-add "$NUM" --owner "$OWNER" --url "$url" >/dev/null
    if [ -n "$blocked" ]; then
      me=$(issue_id "$REPO" "$n")
      IFS=, read -ra bs <<<"$blocked"
      for b in "${bs[@]}"; do
        case $b in
          */*#*) brepo=${b%#*}; bn=${b##*#} ;;
          *) brepo=$REPO; bn=${b#\#} ;;
        esac
        gh api graphql -F issueId="$me" -F blockingIssueId="$(issue_id "$brepo" "$bn")" -f query='
mutation($issueId:ID!,$blockingIssueId:ID!){addBlockedBy(input:{issueId:$issueId,blockingIssueId:$blockingIssueId}){clientMutationId}}' >/dev/null
      done
    fi
    echo "$n"
    ;;
  close)
    n=${1:?ticket number}; shift
    comment=; reason=
    while [ $# -gt 0 ]; do
      case $1 in
        --comment) comment=${2?}; shift 2 ;;
        --not-planned) reason="not planned"; shift ;;
        *) die "close: unknown argument $1" ;;
      esac
    done
    [ -n "$comment" ] || die "close: --comment is required"
    gh issue close "$n" --repo "$REPO" --comment "$comment" ${reason:+--reason "$reason"} >/dev/null
    echo "closed: $n"
    ;;
  *) die "usage: tickets.sh list | show <n> | status <n> <status> | create --title T ... | close <n> --comment TEXT" ;;
esac
