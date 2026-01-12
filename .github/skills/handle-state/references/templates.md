# State encoding templates

The handle state library works best with a fixed number of scalar variables. Anything else
must be encoded as a string.

## Array variables

```bash
# In the state producer function
producer() {
    local -a myarray=("value1" "value2" "value with spaces")
    encoded=$(printf '%s\0' "${myarray[@]}" | base64 -w0)
    hs_persist_state encoded
}

# In a state consumer function
consumer() {
    local encoded
    eval "$(hs_read_persisted_state "$1")"
    declare -a newarray
    mapfile -d '' -t newarray < <(printf '%s' "$encoded" | base64 -d)
    # Use newarray
    echo "${newarray[2]}"
}
# In the caller
state=$(producer)
consumer "$state"  # outputs yelvalue with spaces, the 3rd value
```

## Associative arrays

```bash
# In the state producer function
producer() {
    declare -A myarray=( [apple]="red" [banana]="yellow" [cherry]="dark red" )
    local array_keys array_values
    array_keys=$(printf '%s\0' "${!myarray[@]}" | base64 -w0)
    array_values=$(printf '%s\0' "${myarray[@]}" | base64 -w0)
    hs_persist_state array_keys array_values
}
# In a state consumer function
consumer() {
    local array_keys array_values
    eval "$(hs_read_persisted_state "$1")"
    local -a keys
    local -a values
    mapfile -d '' -t keys < <(printf '%s' "$array_keys" | base64 -d)
    mapfile -d '' -t values < <(printf '%s' "$array_values" | base64 -d)
    local -A newarray
    for i in "${!keys[@]}"; do
      newarray["${keys[i]}"]="${values[i]}"
    done
    # Use newarray
    echo "${newarray[cherry]}"
}
# In the caller
state=$(producer)
consumer "$state"  # outputs dark red, the value associated with 'banana'.
```

## Name references

```bash
# In the producer function
producer() {
    declare -n nameref
    local target1 target2 encoding
    target1=banana
    target2=apple
    nameref=target1
    encoding="${!nameref}"
    hs_persist_state encoding
}
# In the consumer function
consumer() {
    local encoding
    eval "$(hs_read_persisted_state "$1")"
    local target1=yellow
    local target2=red
    local -n nameref=$encoding
    echo $nameref
}
# In the caller
state=$(producer)
consumer "$state"  # outputs yellow, the current value of target1.
```
