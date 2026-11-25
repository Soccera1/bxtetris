# X11 core protocol over a connected socket.

case $OSTYPE in
    darwin*) x11_module=${BASH_SOURCE[0]%/*}/x11-unix.dylib ;;
    *)       x11_module=${BASH_SOURCE[0]%/*}/x11-unix.so ;;
esac

x11_die() {
    printf 'bxtetris: %s\n' "$*" >&2
    exit 1
}

# Bash strings cannot hold NUL. Use hex escapes for output and read
# with a NUL delimiter to recover input as an array of byte values.
x11_read() {
    local fd=$1 remaining=$2 timeout=${3-} chunk status i limit
    packet=()
    while (( remaining > 0 )); do
        limit=$remaining
        if [[ -n $timeout ]]; then
            limit=1
            IFS= read -r -d '' -n 1 -t "$timeout" -u "$fd" chunk
            status=$?
            (( status == 0 )) || return "$status"
            timeout=
        else
            IFS= read -r -d '' -n "$limit" -u "$fd" chunk || return 1
        fi
        for (( i=0; i<${#chunk}; i++ )); do
            printf -v "packet[${#packet[@]}]" '%d' "'${chunk:i:1}"
        done
        (( remaining -= ${#chunk} ))
        if (( ${#chunk} < limit )); then
            packet+=(0)
            (( remaining -= 1 ))
        fi
    done
    return 0
}

x11_u16() {
    local value
    for value; do
        wire+=${octet[value & 255]}${octet[(value >> 8) & 255]}
    done
}

x11_u32() {
    local value
    for value; do
        x11_u16 "$value" "$((value >> 16))"
    done
}

x11_request() {
    local opcode=$1 detail=$2
    wire+=${octet[opcode]}${octet[detail]}
    x11_u16 "$3"
}

x11_pad() {
    local i
    for (( i=$1; i%4; i++ )); do wire+=${octet[0]}; done
}

x11_string() {
    local str=$1
    wire+=${str//\\/\\\\}
    x11_pad "${#str}"
}

x11_send() {
    printf '%b' "$wire" >&"$x_fd" || x11_die 'X11 connection lost'
    wire=
}

x11_get() {
    local offset=$1 size=$2 i
    number=0
    for (( i=size-1; i>=0; i-- )); do
        (( number = (number << 8) | packet[offset+i] ))
    done
}

# Xauthority records use big-endian 16-bit lengths.
x11_auth_field() {
    x11_read "$auth_fd" 2 || return 1
    x11_read "$auth_fd" "$((packet[0]*256 + packet[1]))" || return 1
    field=
    local item
    for item in "${packet[@]}"; do field+=${octet[item]}; done
}

x11_cookie() {
    local auth_fd family rank best=0 field name match_display i
    local authority=${XAUTHORITY-"${HOME:-}/.Xauthority"}
    local local_host=${XAUTHLOCALHOSTNAME:-$HOSTNAME}
    local -a ipv4=()
    cookie=
    if [[ $host == localhost ]]; then
        ipv4=(127 0 0 1)
    elif [[ $host =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]]; then
        for i in 1 2 3 4; do
            ipv4+=("$((10#${BASH_REMATCH[i]}))")
        done
    fi
    [[ -r $authority ]] || return 0
    exec {auth_fd}<"$authority" || return 0
    while x11_read "$auth_fd" 2; do
        family=$((packet[0]*256 + packet[1]))
        x11_auth_field || break
        rank=0
        case $family in
            0)
                if (( ${#ipv4[@]} == 4 )) && [[ ${packet[*]} == "${ipv4[*]}" ]]; then rank=3; fi
                ;;
            6)
                if [[ $host == ::1 && ${packet[*]} == '0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 1' ]]; then rank=3; fi
                ;;
            256)
                printf -v name '%b' "$field"
                if [[ $local_display == 1 && $name == "$local_host" ]]; then rank=2; fi
                ;;
            65535) rank=1 ;;
        esac
        x11_auth_field || break
        printf -v match_display '%b' "$field"
        if [[ -n $match_display && $match_display != "$display" ]]; then rank=0; fi
        x11_auth_field || break
        printf -v name '%b' "$field"
        x11_auth_field || break
        if (( rank > best && ${#packet[@]} == 16 )) && [[ $name == MIT-MAGIC-COOKIE-1 ]]; then
            best=$rank
            cookie=$field
        fi
    done
    exec {auth_fd}<&-
}

x11_open_unix() {
    local socket=/tmp/.X11-unix/X$1
    if [[ ! -r $x11_module ]]; then
        printf 'bxtetris: missing %s. See README.md for the Unix socket module.\n' "${x11_module##*/}" >&2
        return 1
    fi
    enable -f "$x11_module" bxt_x11_connect || return 1
    if bxt_x11_connect "$socket" 2>/dev/null ||
        { [[ $OSTYPE == linux* ]] && bxt_x11_connect "@$socket" 2>/dev/null; }; then
        enable -d bxt_x11_connect
        return 0
    fi
    enable -d bxt_x11_connect
    printf 'bxtetris: cannot connect to X11 Unix socket %s\n' "$socket" >&2
    return 1
}

x11_open_transport() {
    local port implicit_local=0
    case $host in
        '')
            local_display=1
            implicit_local=1
            if x11_open_unix "$display" 2>/dev/null; then return 0; fi
            host=127.0.0.1
            ;;
        unix|unix/|local/|*/unix)
            local_display=1
            host=
            x11_open_unix "$display" || exit 1
            return 0
            ;;
        *)
            host=${host#tcp/}
            host=${host#\[}
            host=${host%\]}
            host=${host:-127.0.0.1}
            ;;
    esac
    case $host in
        localhost|127.0.0.1|::1) local_display=1 ;;
    esac
    port=$((6000 + display))
    (( port <= 65535 )) || x11_die 'DISPLAY number is out of range'
    if { exec {x_fd}<>"/dev/tcp/$host/$port"; } 2>/dev/null; then return 0; fi
    if (( implicit_local )); then
        if [[ ! -r $x11_module ]]; then
            x11_die 'cannot connect over loopback TCP. See README.md for the Unix socket build command.'
        fi
        x11_die "cannot connect to X11 display :$display over a Unix socket or loopback TCP"
    fi
    x11_die "cannot connect to $host port $port (X11 TCP display $display)"
}

x11_connect() {
    local host display screen i formats vendor root_count offset depth_count
    local visual_count visual id cookie local_display=0
    for (( i=0; i<256; i++ )); do printf -v 'octet[i]' '\\x%02x' "$i"; done
    [[ ${DISPLAY-} =~ ^(.*):([0-9]{1,5})(\.([0-9]{1,3}))?$ ]] ||
        x11_die 'set DISPLAY to an X11 display, such as :0 or 127.0.0.1:1'
    host=${BASH_REMATCH[1]}
    display=$((10#${BASH_REMATCH[2]}))
    screen=$((10#${BASH_REMATCH[4]:-0}))
    x11_open_transport
    x11_cookie
    wire='l\x00'
    if [[ -n $cookie ]]; then
        x11_u16 11 0 18 16 0
        x11_string MIT-MAGIC-COOKIE-1
        wire+=$cookie
    else
        x11_u16 11 0 0 0 0
    fi
    x11_send
    x11_read "$x_fd" 8 || x11_die 'X11 setup did not receive a reply'
    (( packet[0] == 1 )) || x11_die 'X11 setup rejected the connection. Check DISPLAY and XAUTHORITY.'
    x11_get 6 2
    x11_read "$x_fd" "$((number*4))" || x11_die 'incomplete X11 setup reply'
    x11_get 4 4
    resource_base=$number
    x11_get 8 4
    resource_step=$((number & -number))
    x11_get 16 2
    vendor=$number
    root_count=${packet[20]} formats=${packet[21]}
    key_first=${packet[26]} key_last=${packet[27]}
    (( screen < root_count )) || x11_die "X11 screen $screen does not exist"
    offset=$((32 + (vendor+3)/4*4 + formats*8))
    for (( i=0; i<=screen; i++ )); do
        x11_get "$offset" 4
        root=$number
        x11_get "$((offset+32))" 4
        visual=$number
        depth=${packet[offset+38]}
        depth_count=${packet[offset+39]}
        (( offset += 40 ))
        while (( depth_count-- > 0 )); do
            x11_get "$((offset+2))" 2
            visual_count=$number
            (( offset += 8 ))
            while (( visual_count-- > 0 )); do
                x11_get "$offset" 4
                id=$number
                if (( i == screen && id == visual )); then
                    (( packet[offset+4] == 4 )) || x11_die 'the default X11 visual must be TrueColor'
                    x11_get "$((offset+8))" 4
                    red_mask=$number
                    x11_get "$((offset+12))" 4
                    green_mask=$number
                    x11_get "$((offset+16))" 4
                    blue_mask=$number
                    return 0
                fi
                (( offset += 24 ))
            done
        done
    done
    x11_die 'default X11 visual missing from setup reply'
}

x11_error() {
    x11_die "X11 error ${packet[1]} on request opcode ${packet[10]}"
}

x11_atom() {
    local name=$1
    x11_request 16 0 "$((2 + (${#name}+3)/4))" # InternAtom
    x11_u16 "${#name}" 0
    x11_string "$name"
    x11_send
    x11_read "$x_fd" 32 || x11_die 'X11 connection closed'
    if (( packet[0] == 0 )); then x11_error; fi
    (( packet[0] == 1 )) || x11_die 'unexpected X11 message while interning an atom'
    x11_get 8 4
}

x11_channel() {
    local channel=$1 mask=$2 unit scaled
    unit=$((mask & -mask))
    scaled=$(((channel * (mask/unit) + 127)/255))
    number=$((scaled*unit))
}

x11_pixel() {
    local rgb=$1 red green
    x11_channel "$((rgb >> 16))" "$red_mask"
    red=$number
    x11_channel "$((rgb >> 8 & 255))" "$green_mask"
    green=$number
    x11_channel "$((rgb & 255))" "$blue_mask"
    (( number |= red | green ))
}

x11_open_window() {
    local width=$1 height=$2 title=$3 rgb font pixel
    shift 3
    window=$((resource_base | resource_step))
    canvas=$((resource_base | 2*resource_step))
    font=$((resource_base | 3*resource_step))
    x11_atom WM_PROTOCOLS
    wm_protocols=$number
    x11_atom WM_DELETE_WINDOW
    wm_delete=$number
    x11_pixel "$1"
    pixel=$number

    # Inherit depth and visual. Select KeyPress, Exposure and StructureNotify.
    x11_request 1 0 10 # CreateWindow
    x11_u32 "$window" "$root"
    x11_u16 0 0 "$width" "$height" 0 1
    x11_u32 0 "$((1<<1 | 1<<11))" "$pixel" "$((1 | 1<<15 | 1<<17))"

    x11_request 18 0 "$((6 + (${#title}+3)/4))" # WM_NAME, STRING
    x11_u32 "$window" 39 31
    x11_u32 8 "${#title}"
    x11_string "$title"
    x11_request 18 0 24 # WM_NORMAL_HINTS, WM_SIZE_HINTS
    x11_u32 "$window" 40 41 32 18
    x11_u32 48 0 0 0 0 "$width" "$height" "$width" "$height" 0 0 0 0 0 0 0 0 0
    x11_request 18 0 7 # WM_PROTOCOLS, ATOM
    x11_u32 "$window" "$wm_protocols" 4 32 1 "$wm_delete"

    x11_request 53 "$depth" 4 # CreatePixmap
    x11_u32 "$canvas" "$window"
    x11_u16 "$width" "$height"
    x11_request 45 0 5 # OpenFont
    x11_u32 "$font"
    x11_u16 5 0
    x11_string fixed
    gc=()
    for rgb in "$@"; do
        x11_pixel "$rgb"
        gc+=("$((resource_base | (${#gc[@]}+4)*resource_step))")
        x11_request 55 0 7 # CreateGC with foreground, font, and graphics exposures off
        x11_u32 "${gc[-1]}" "$canvas" "$((1<<2 | 1<<14 | 1<<16))" "$number" "$font" 0
    done
    x11_request 46 0 2 # CloseFont (the GCs retain it)
    x11_u32 "$font"
    x11_request 8 0 2 # MapWindow
    x11_u32 "$window"
    x11_send
}

# keys is consumed by the launcher after it sources this file.
# shellcheck disable=SC2034
x11_keymap() {
    local count=$((key_last-key_first+1)) per_key amount code column
    x11_request 101 0 2 # GetKeyboardMapping
    wire+=${octet[key_first]}${octet[count]}
    x11_u16 0
    x11_send
    while :; do
        x11_read "$x_fd" 32 || x11_die 'X11 connection closed'
        case $((packet[0] & 127)) in
            0) x11_error ;;
            1) break ;;
            2|12|17|33) pending_events+=("${packet[*]}") ;;
        esac
    done
    per_key=${packet[1]}
    x11_get 4 4
    amount=$((number*4))
    x11_read "$x_fd" "$amount" || x11_die 'incomplete X11 keymap reply'
    keys=()
    for (( code=key_first; code<=key_last; code++ )); do
        for (( column=0; column<per_key; column++ )); do
            x11_get "$(((code-key_first)*per_key*4+column*4))" 4
            case $number in
                65361|97|65) keys[code]=left ;;
                65363|100|68) keys[code]=right ;;
                65364|115|83) keys[code]=down ;;
                65362|120|88) keys[code]=rotate ;;
                122|90) keys[code]=reverse ;;
                32) keys[code]=drop ;;
                112|80) keys[code]=pause ;;
                114|82) keys[code]=restart ;;
                65307|113|81) keys[code]=quit ;;
                *) continue ;;
            esac
            break
        done
    done
}

x11_rect() {
    local color=$1 saved_wire=$wire
    shift
    wire=
    x11_u16 "$@"
    rectangles[color]+=$wire
    wire=$saved_wire
}

x11_fill() {
    local color
    for color in "${!rectangles[@]}"; do
        x11_request 70 0 "$((3 + ${#rectangles[color]}/16))" # PolyFillRectangle
        x11_u32 "$canvas" "${gc[color]}"
        wire+=${rectangles[color]}
    done
    rectangles=()
}

x11_text() {
    local color=$1 x=$2 y=$3 label=$4 length=${#4}
    x11_request 74 0 "$((4 + (length+5)/4))" # PolyText8
    x11_u32 "$canvas" "${gc[color]}"
    x11_u16 "$x" "$y"
    wire+=${octet[length]}${octet[0]}${label//\\/\\\\}
    x11_pad "$((length+2))"
}

x11_present() {
    x11_request 62 0 7 # CopyArea
    x11_u32 "$canvas" "$window" "${gc[0]}"
    x11_u16 0 0 0 0 "$1" "$2"
    x11_send
}
