#!/bin/bash
#set -xe

# If the device name is xxx, a record is created xxx.zt.exmple.com
DOMAIN="example.com"
RECORD_FORMAT="%s.zt"

# https://dash.cloudflare.com/profile/api-tokens
CLOUDFLARE_API_ENDPOINT="https://api.cloudflare.com/client/v4"
CLOUDFLARE_ZONE_ID="xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
CLOUDFLARE_TOKEN="xxxxxxxxxx_xxxxxxxxxxxxxxxxxxxxxxxxxxxxx"

# https://my.zerotier.com/account
ZEROTIER_TOKEN="xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
ZEROTIER_NETWORK="xxxxxxxxxxxxxxxx"

get_zt_members() {
    response=$(curl -s -H "Authorization: Bearer $ZEROTIER_TOKEN" \
        "https://my.zerotier.com/api/network/$ZEROTIER_NETWORK/member")
    echo "$response" | jq -c '.[] | select(.config.ipAssignments != null) | {name: .name, nodeId: .nodeId, ipAssignments: .config.ipAssignments}'
}

upsert_dns_record() {
    local name type content
    name="$1"
    type="$2"
    content="$3"

    record_id=$(curl -s -X GET "$CLOUDFLARE_API_ENDPOINT/zones/$CLOUDFLARE_ZONE_ID/dns_records?type=$type&name=$name.$DOMAIN" \
        -H "Authorization: Bearer $CLOUDFLARE_TOKEN" \
        -H "Content-Type: application/json" | jq -r ".result[0].id")
    if [ -n "$record_id" ] && [ "$record_id" != "null" ]; then
        echo "update $name -> $content"
        response=$(curl -s -X PUT "$CLOUDFLARE_API_ENDPOINT/zones/$CLOUDFLARE_ZONE_ID/dns_records/$record_id" \
            -H "Authorization: Bearer $CLOUDFLARE_TOKEN" \
            -H "Content-Type: application/json" \
            --data "{\"type\":\"$type\",\"name\":\"$name\",\"content\":\"$content\",\"ttl\":1,\"proxied\":false}")
    else
        echo "create $name -> $content"
        response=$(curl -s -X POST "$CLOUDFLARE_API_ENDPOINT/zones/$CLOUDFLARE_ZONE_ID/dns_records" \
            -H "Authorization: Bearer $CLOUDFLARE_TOKEN" \
            -H "Content-Type: application/json" \
            --data "{\"type\":\"$type\",\"name\":\"$name\",\"content\":\"$content\",\"ttl\":1,\"proxied\":false}")
    fi

    echo "$response" | jq '.success'
}

main() {
    members=$(get_zt_members)

    for member in $members; do
        name=$(printf "$RECORD_FORMAT" $(echo "$member" | jq -r '.name'))
        ipv4s=$(echo "$member" | jq -r '.ipAssignments[] | select(test("\\."))')
        ipv6s=$(echo "$member" | jq -r '.ipAssignments[] | select(test(":"))')

        for ip in $ipv4s ; do
            upsert_dns_record "$name" "A" "$ip"
        done
        for ip in $ipv6s ; do
            upsert_dns_record "$name" "AAAA" "$ip"
        done
    done
}

main
