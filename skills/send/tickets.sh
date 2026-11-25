#!/usr/bin/env bash
# Board operations on the project's GitHub board: every gh call the skills make on a ticket.
# Run from inside the project (project.sh, next to this script, names the code repo, the Project's
# owner and number, and the key). A ticket is an issue in the code repo; <n> is its issue number.
# Wherever a ticket is named, <n>, #<n> and <KEY>-<n> (the board's key) all work; output is always <n>.
#   tickets.sh list                      unblocked To do tickets, urgent first, then lowest number;
#                                        one per line: <n> TAB <labels, comma-joined> TAB <title>
#   tickets.sh show <n>                  one JSON object: number, title, body, state, status,
#                                        labels (names), comments ({author, body}),
#                                        blockers ({ref: owner/name#n, state})
#   tickets.sh status <n> <status>       todo | in-progress | done (any case, spaces or hyphens);
#                                        prints `<n>: <Status>`
#   tickets.sh create --title T [--body B] [--label a,b] [--blocked-by n,owner/name#n]
#                                        creates the issue, adds it to the Project, prints <n>
#   tickets.sh block <n> <n|owner/name#n>
#                                        marks ticket <n> as blocked by the other ticket; prints `<n>: blocked by <ref>`
#   tickets.sh edit <n> [--title T] [--body B]
#                                        replaces the title, the body or both (one is required);
#                                        prints `<n>: edited`
#   tickets.sh close <n> --comment TEXT [--not-planned]
#                                        closes with the comment; --not-planned for a ticket with no code
# Item lists pass an explicit limit of 200 (gh's default is 30). Blocked-by goes through GraphQL.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
die() { echo "tickets.sh: $*" >&2; exit 1; }

lookup=$(bash "$here/project.sh")
field() { sed -n "s/^$1: //p" <<<"$lookup"; }
[ "$(field project)" != none ] && [ "$(field board)" != none ] || die "$(field reason)"
[ "$(field board)" = github ] || die "board is $(field board), not github"
REPO=$(field repo); OWNER=$(field owner); NUM=$(field number); KEY=$(field key)
[ -n "$REPO" ] && [ -n "$OWNER" ] && [ -n "$NUM" ] ||
  die "$(field dir)/.claude/project.md needs project (the Project's number), and repo when the checkout has no origin"

# num <ticket>: the issue number of <n>, #<n> or <KEY>-<n>; any other key fails
num() {
  local t=${1#\#}
  case $t in
    '') die "missing ticket number" ;;
    *[!0-9]*)
      [ -n "$KEY" ] || die "$1 is no ticket of this board: its tickets are plain numbers"
      [ "${t%-*}" = "$KEY" ] || die "$1 is no ticket of this board (key $KEY)"
      t=${t##*-}
      case $t in ''|*[!0-9]*) die "$1 is no ticket id" ;; esac ;;
  esac
  echo "$t"
}

items() { gh project item-list "$NUM" --owner "$OWNER" -L 200 --format json; }

# item_of <n>: the Project item of ticket <n> as JSON, or empty when it is not on the Project.
# A full list (200 items) without the ticket may just have cut it off: fail instead of guessing.
item_of() {
  local all; all=$(items)
  jq -c --argjson n "$1" '[.items[] | select(.content.number == $n)][0] // empty' <<<"$all" | {
    read -r found || found=
    if [ -z "$found" ] && [ "$(jq '.items | length' <<<"$all")" -ge 200 ]; then
      die "ticket $1 not found in the first 200 Project items: the board exceeds the item-list limit"
    fi
    printf '%s' "$found"
  }
}

# issue_id <owner/name> <n>: node id
issue_id() { gh issue view "$2" --repo "$1" --json id | jq -r .id; }

# blockers <n>: JSON array of {ref, state}
blockers() {
  gh api graphql -F owner="${REPO%%/*}" -F name="${REPO#*/}" -F number="$1" -f query='
query($owner:String!,$name:String!,$number:Int!){repository(owner:$owner,name:$name){issue(number:$number){blockedBy(first:50){nodes{number state repository{nameWithOwner}}}}}}' |
    jq -c '[.data.repository.issue.blockedBy.nodes[] | {ref: "\(.repository.nameWithOwner)#\(.number)", state}]'
}

# block <n> <ref>: ref is a ticket of this board or owner/name#n
block() {
  local b=$2 brepo bn
  case $b in
    */*#*) brepo=${b%#*}; bn=${b##*#} ;;
    *) brepo=$REPO; bn=$(num "$b") ;;
  esac
  gh api graphql -F issueId="$(issue_id "$REPO" "$1")" -F blockingIssueId="$(issue_id "$brepo" "$bn")" -f query='
mutation($issueId:ID!,$blockingIssueId:ID!){addBlockedBy(input:{issueId:$issueId,blockingIssueId:$blockingIssueId}){clientMutationId}}' >/dev/null
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
    n=$(num "${1:?ticket number}")
    issue=$(gh issue view "$n" --repo "$REPO" --json number,title,body,labels,comments,state)
    item=$(item_of "$n") || exit 1
    status=$(jq -r '.status // ""' <<<"${item:-null}")
    jq --arg status "$status" --argjson blockers "$(blockers "$n")" '
      {number, title, body, state, status: $status,
       labels: [.labels[].name],
       comments: [.comments[] | {author: .author.login, body}],
       blockers: $blockers}' <<<"$issue"
    ;;
  status)
    n=$(num "${1:?ticket number}"); want=${2:?status}
    case $(tr '[:upper:] _' '[:lower:]--' <<<"$want") in
      todo|to-do) name=Todo ;;
      in-progress) name="In Progress" ;;
      done) name=Done ;;
      *) die "unknown status $want (todo, in-progress, done)" ;;
    esac
    item=$(item_of "$n") || exit 1
    [ -n "$item" ] || die "ticket $n is not on the Project"
    item=$(jq -r .id <<<"$item")
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
    # the issue exists from here on: a later failure names it, so the caller does not create it again
    gh project item-add "$NUM" --owner "$OWNER" --url "$url" >/dev/null ||
      die "create: issue $n exists ($url) but was not added to Project $NUM"
    if [ -n "$blocked" ]; then
      IFS=, read -ra bs <<<"$blocked"
      for b in "${bs[@]}"; do
        block "$n" "$b" || die "create: issue $n exists ($url) but is not marked as blocked by $b"
      done
    fi
    echo "$n"
    ;;
  block)
    n=$(num "${1:?ticket number}")
    block "$n" "${2:?blocking ticket}"
    echo "$n: blocked by $2"
    ;;
  edit)
    n=$(num "${1:?ticket number}"); shift
    args=()
    while [ $# -gt 0 ]; do
      case $1 in
        --title) [ -n "${2?}" ] || die "edit: --title must not be empty"; args+=(--title "$2"); shift 2 ;;
        --body) args+=(--body "${2?}"); shift 2 ;;
        *) die "edit: unknown argument $1" ;;
      esac
    done
    [ ${#args[@]} -gt 0 ] || die "edit: give --title, --body or both"
    gh issue edit "$n" --repo "$REPO" "${args[@]}" >/dev/null
    echo "$n: edited"
    ;;
  close)
    n=$(num "${1:?ticket number}"); shift
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
  *) die "usage: tickets.sh list | show <n> | status <n> <status> | create --title T ... | block <n> <ref> | edit <n> [--title T] [--body B] | close <n> --comment TEXT" ;;
esac
