# State encoding templates

The current `handle_state` API works best with a fixed set of local scalar
variables. Anything else should be encoded into one or more scalars before
calling `hs_persist_state_as_code`.

## Indexed arrays

```bash
producer() {
    local -a myarray=("value1" "value2" "value with spaces")
    local encoded
    encoded=$(printf '%s\0' "${myarray[@]}" | base64 -w0)
    hs_persist_state_as_code "$@" -- encoded
}

consumer() {
    local encoded
    local -a newarray
    hs_read_persisted_state "$@" -- encoded
    mapfile -d '' -t newarray < <(printf '%s' "$encoded" | base64 -d)
    echo "${newarray[2]}"
}

local state=""
producer -S state
consumer -S state
```

## Associative arrays

```bash
producer() {
    local -A myarray=([apple]="red" [banana]="yellow" [cherry]="dark red")
    local array_keys array_values
    array_keys=$(printf '%s\0' "${!myarray[@]}" | base64 -w0)
    array_values=$(printf '%s\0' "${myarray[@]}" | base64 -w0)
    hs_persist_state_as_code "$@" -- array_keys array_values
}

consumer() {
    local array_keys array_values
    local -a keys values
    local -A newarray
    local i
    hs_read_persisted_state "$@" -- array_keys array_values
    mapfile -d '' -t keys < <(printf '%s' "$array_keys" | base64 -d)
    mapfile -d '' -t values < <(printf '%s' "$array_values" | base64 -d)
    for i in "${!keys[@]}"; do
      newarray["${keys[i]}"]="${values[i]}"
    done
    echo "${newarray[cherry]}"
}

local state=""
producer -S state
consumer -S state
```

## Namerefs

```bash
producer() {
    local target1=banana
    local target2=apple
    local -n nameref=target1
    local encoding
    encoding="${!nameref}"
    hs_persist_state_as_code "$@" -- encoding
}

consumer() {
    local encoding
    local target1=yellow
    local target2=red
    hs_read_persisted_state "$@" -- encoding
    local -n nameref=$encoding
    echo "$nameref"
}

local state=""
producer -S state
consumer -S state
```
