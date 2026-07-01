#!/usr/bin/env bash
# marathon.d/phase9.sh — onboarding, docs, completions.
#
#   marathon quickstart              print step-by-step onboarding
#   marathon docs [TOPIC]            open docs/<topic>.md in $PAGER
#   marathon completions bash|zsh|fish   print shell completion
#
# shellcheck source=common.sh
# shellcheck disable=SC2154

cmd_quickstart() {
    cat <<'HELP'

  ▸ Marathon dev quickstart

  1. Verify your environment:
       marathon doctor
     Anything red → 'marathon doctor --fix' will try to repair it.

  2. Register your devices (if not already):
       marathon device add l5   librem5    root@marathon.local  'Librem 5'
       marathon device add cm5  hackberry  root@marathon.local  'HackberryPi CM5'
       marathon device use l5

  3. See what's on the device right now:
       marathon status
       marathon apps

  4. Iterate on the shell:
       # after editing shell/ or marathon-ui/
       marathon deploy         # build + push + verify hash

  5. Interact with the device:
       marathon wake
       marathon unlock
       marathon launch settings
       marathon snap my-test

  6. Watch what happens live:
       marathon monitor cgroup     # every uclamp/freeze transition
       marathon monitor logs       # tail crash.log
       marathon monitor wifi

  7. Build a new app:
       marathon app new my-app
       marathon app watch my-app   # auto-repackage + install on save

  8. Multi-device:
       marathon --device cm5 status
       marathon all status

  9. Save + replay a scenario:
       marathon session new doze-test
       marathon session record doze-test wake
       marathon session record doze-test snap doze-baseline
       marathon session record doze-test power
       marathon session record doze-test snap doze-entered
       marathon session run doze-test

  Full help:    marathon --help
  CLI ref:      marathon docs cli        (docs/DEV_CLI.md)
  All docs:     marathon docs

HELP
}

cmd_docs() {
    local topic="${1:-}"
    local docs_dir="$MARATHON_SRC/docs"
    if [ -z "$topic" ]; then
        echo "  Marathon docs at $docs_dir:"
        find "$docs_dir" -maxdepth 2 -name '*.md' -printf '    %f\n' 2>/dev/null | sort
        return
    fi
    local file
    # Special aliases for verbs that don't literally match a filename.
    case "$topic" in
        cli|dev|tool|tools) topic=DEV_CLI ;;
        workflow)           topic=DEVELOPMENT_WORKFLOW ;;
        arch|architecture)  topic=ARCHITECTURE ;;
        design|ui)          topic=UI_DESIGN_SYSTEM ;;
        rules|coding)       topic=CODING_RULES ;;
    esac
    for candidate in \
        "$docs_dir/$topic" \
        "$docs_dir/$topic.md" \
        "$docs_dir/${topic^^}.md" \
        "$docs_dir/${topic^^}_GUIDE.md"; do
        if [ -f "$candidate" ]; then
            file="$candidate"
            break
        fi
    done
    if [ -z "$file" ]; then
        marathon::error "no doc matching '$topic' in $docs_dir"
        return 1
    fi
    "${PAGER:-less}" "$file"
}

cmd_completions() {
    local shell="${1:-bash}"
    case "$shell" in
        bash) _completions_bash ;;
        zsh)  _completions_zsh ;;
        fish) _completions_fish ;;
        *) marathon::error "usage: marathon completions <bash|zsh|fish>"; return 2 ;;
    esac
}

_completions_bash() {
    cat <<'BASH'
# marathon dev CLI bash completion — save to
#   ~/.local/share/bash-completion/completions/marathon
# or eval:  eval "$(marathon completions bash)"

_marathon() {
    local cur prev verbs
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    verbs="status deploy reset wake unlock snap logs apps launch
           tap swipe power doze freq irqs wakeups cgroup monitor
           modem wifi gov scheduler fuel-gauge backlight
           app device all compare
           build flash fmt lint audit changelog
           session bench
           doctor quickstart docs completions --help --device --host"
    case "$prev" in
        launch) COMPREPLY=( $(compgen -W "phone messages mail browser store music camera gallery maps calendar clock calculator notes settings" -- "$cur") ); return ;;
        --device|-d) COMPREPLY=( $(compgen -W "l5 cm5 qemu" -- "$cur") ); return ;;
        app) COMPREPLY=( $(compgen -W "new run package validate install watch registry permissions" -- "$cur") ); return ;;
        device) COMPREPLY=( $(compgen -W "list current use add probe" -- "$cur") ); return ;;
        monitor) COMPREPLY=( $(compgen -W "cgroup logs wifi modem freq bl wakeups" -- "$cur") ); return ;;
        session) COMPREPLY=( $(compgen -W "new record run list rm diff" -- "$cur") ); return ;;
        bench) COMPREPLY=( $(compgen -W "doze wake foreground-boost battery-idle" -- "$cur") ); return ;;
        gov) COMPREPLY=( $(compgen -W "ondemand schedutil conservative performance powersave" -- "$cur") ); return ;;
    esac
    COMPREPLY=( $(compgen -W "$verbs" -- "$cur") )
}
complete -F _marathon marathon
BASH
}

_completions_zsh() {
    cat <<'ZSH'
# marathon zsh completion — save to $fpath as _marathon
# or eval:  eval "$(marathon completions zsh)"

_marathon() {
    local -a verbs
    verbs=(
        'status:shell + device state at a glance'
        'deploy:build shell + push + restart greetd'
        'reset:systemctl restart greetd'
        'wake:force backlight on'
        'unlock:enter PIN'
        'snap:screenshot device'
        'logs:tail shell log'
        'apps:running app-runners + cgroup state'
        'launch:launch an app by ID'
        'doctor:environment + device health check'
        'app:app-dev lifecycle'
        'monitor:live monitor (cgroup/logs/wifi/…)'
        'session:record + replay test scenarios'
        'bench:canned benchmarks'
        'device:multi-device commands'
        'all:run verb on every reachable device'
        'quickstart:onboarding walkthrough'
    )
    _describe 'marathon verb' verbs
}
compdef _marathon marathon
ZSH
}

_completions_fish() {
    cat <<'FISH'
# marathon fish completion — save to
#   ~/.config/fish/completions/marathon.fish
# or eval:  marathon completions fish | source

complete -c marathon -f
complete -c marathon -n '__fish_use_subcommand' -a 'status'    -d 'shell + device state'
complete -c marathon -n '__fish_use_subcommand' -a 'deploy'    -d 'build + push shell binary'
complete -c marathon -n '__fish_use_subcommand' -a 'reset'     -d 'restart greetd'
complete -c marathon -n '__fish_use_subcommand' -a 'wake'      -d 'force backlight on'
complete -c marathon -n '__fish_use_subcommand' -a 'unlock'    -d 'enter PIN'
complete -c marathon -n '__fish_use_subcommand' -a 'snap'      -d 'screenshot device'
complete -c marathon -n '__fish_use_subcommand' -a 'logs'      -d 'tail shell log'
complete -c marathon -n '__fish_use_subcommand' -a 'apps'      -d 'running runners + cgroup state'
complete -c marathon -n '__fish_use_subcommand' -a 'launch'    -d 'launch app by ID'
complete -c marathon -n '__fish_use_subcommand' -a 'doctor'    -d 'env health check'
complete -c marathon -n '__fish_use_subcommand' -a 'app'       -d 'app-dev lifecycle'
complete -c marathon -n '__fish_use_subcommand' -a 'monitor'   -d 'live monitor'
complete -c marathon -n '__fish_use_subcommand' -a 'quickstart' -d 'onboarding walkthrough'
FISH
}
