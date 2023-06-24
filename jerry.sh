#!/bin/sh

JERRY_VERSION=2.0.0

# TODO: Add spaces for all launchers

anilist_base="https://graphql.anilist.co"
config_file="$HOME/.config/jerry/jerry.conf"
jerry_editor=${VISUAL:-${EDITOR}}
tmp_dir="/tmp/jerry"
tmp_position="/tmp/jerry_position"
image_config_path="$HOME/.config/rofi/styles/launcher.rasi"

if [ "$1" = "--edit" ] || [ "$1" = "-e" ]; then
    if [ -f "$config_file" ]; then
        #shellcheck disable=1090
        . "${config_file}"
        [ -z "$jerry_editor" ] && jerry_editor="vim"
        "$jerry_editor" "$config_file"
    fi
    exit 0
fi

cleanup() {
    rm -rf "$tmp_dir" 2>/dev/null
    if [ "$image_preview" = "1" ] && [ "$use_external_menu" = "0" ]; then
        killall ueberzugpp 2>/dev/null
        rm /tmp/ueberzugpp-* 2>/dev/null
    fi
}
trap cleanup EXIT INT TERM

applications="$HOME/.local/share/applications/jerry"
images_cache_dir="/tmp/jerry/jerry-images"

command -v bat >/dev/null 2>&1 && display="bat" || display="less"
case "$(uname -s)" in
    MINGW* | *Msys) separator=';' && path_thing='' && sed="sed" ;;
    *arwin) sed="gsed" ;;
    *) separator=':' && path_thing="\\" && sed="sed" ;;
esac
command -v notify-send >/dev/null 2>&1 && notify="true" || notify="false"
send_notification() {
    [ "$json_output" = 1 ] && return
    if [ "$use_external_menu" = "0" ] || [ "$use_external_menu" = "" ]; then
        [ -z "$4" ] && printf "\33[2K\r\033[1;34m%s\n\033[0m" "$1" && return
        [ -n "$4" ] && printf "\33[2K\r\033[1;34m%s - %s\n\033[0m" "$1" "$4" && return
    fi
    [ -z "$2" ] && timeout=3000 || timeout="$2"
    if [ "$notify" = "true" ]; then
        [ -z "$3" ] && notify-send "$1" "$4" -t "$timeout"
        [ -n "$3" ] && notify-send "$1" "$4" -t "$timeout" -i "$3"
        # -h string:x-dunst-stack-tag:tes
    fi
}
dep_ch() {
    for dep; do
        command -v "$dep" >/dev/null || send_notification "Program \"$dep\" not found. Please install it."
    done
}
dep_ch "grep" "$sed" "awk" "curl" "fzf" "mpv" || true

if [ "$use_external_menu" = "1" ]; then
    dep_ch "rofi" || true
fi

configuration() {
    [ -n "$XDG_CONFIG_HOME" ] && config_dir="$XDG_CONFIG_HOME/jerry" || config_dir="$HOME/.config/jerry"
    [ -n "$XDG_DATA_HOME" ] && data_dir="$XDG_DATA_HOME/jerry" || data_dir="$HOME/.local/share/jerry"
    [ ! -d "$config_dir" ] && mkdir -p "$config_dir"
    [ ! -d "$data_dir" ] && mkdir -p "$data_dir"
    #shellcheck disable=1090
    [ -f "$config_file" ] && . "${config_file}"
    [ -z "$player" ] && player="mpv"
    [ -z "$provider" ] && provider="9anime"
    [ -z "$video_provider" ] && video_provider="Vidstream"
    [ -z "$base_helper_url" ] && base_helper_url="https://9anime.eltik.net"
    [ -z "$download_dir" ] && download_dir="$PWD"
    [ -z "$manga_dir" ] && manga_dir="$data_dir/jerry-manga"
    [ -z "$history_file" ] && history_file="$data_dir/jerry_history.txt"
    [ -z "$subs_language" ] && subs_language="english"
    subs_language="$(printf "%s" "$subs_language" | cut -c2-)"
    [ -z "$use_external_menu" ] && use_external_menu=1
    [ -z "$image_preview" ] && image_preview=1
    [ -z "$preview_window_size" ] && preview_window_size=up:60%:wrap
    [ -z "$ueberzug_x" ] && ueberzug_x=10
    [ -z "$ueberzug_y" ] && ueberzug_y=3
    [ -z "$ueberzug_max_width" ] && ueberzug_max_width=$(($(tput lines) / 2))
    [ -z "$ueberzug_max_height" ] && ueberzug_max_height=$(($(tput lines) / 2))
    [ -z "$json_output" ] && json_output=0
}

check_credentials() {
    [ -f "$data_dir/anilist_token.txt" ] && access_token=$(cat "$data_dir/anilist_token.txt")
    [ -z "$access_token" ] && printf "Paste your access token from this page:
https://anilist.co/api/v2/oauth/authorize?client_id=9857&response_type=token : " && read -r access_token &&
        echo "$access_token" >"$data_dir/anilist_token.txt"
    [ -f "$data_dir/anilist_user_id.txt" ] && user_id=$(cat "$data_dir/anilist_user_id.txt")
    [ -z "$user_id" ] &&
        user_id=$(curl -s -X POST "$anilist_base" \
            -H "Content-Type: application/json" \
            -H "Accept: application/json" \
            -H "Authorization: Bearer $access_token" \
            -d "{\"query\":\"query { Viewer { id } }\"}" | $sed -nE "s@.*\"id\":([0-9]*).*@\1@p") &&
        echo "$user_id" >"$data_dir/anilist_user_id.txt"
}

#### HELPER FUNCTIONS ####

get_input() {
    if [ "$use_external_menu" = "0" ]; then
        printf "%s" "$1" && read -r query
    else
        if [ -n "$rofi_prompt_config" ]; then
            query=$(printf "" | rofi -theme "$rofi_prompt_config" -sort -dmenu -i -width 1500 -p "" -mesg "$1")
        else
            query=$(printf "" | launcher "$1")
        fi
    fi
}

generate_desktop() {
    cat <<EOF
[Desktop Entry]
Name=$1
Exec=echo %k %c
Icon=$2
Type=Application
Categories=jerry;
EOF
}

launcher() {
    case "$use_external_menu" in
        1)
            [ -z "$2" ] && rofi -sort -dmenu -i -width 1500 -p "" -mesg "$1"
            [ -n "$2" ] && rofi -sort -dmenu -i -width 1500 -p "" -mesg "$1" -display-columns "$2"
            ;;
        *)
            [ -z "$2" ] && fzf --reverse --prompt "$1"
            [ -n "$2" ] && fzf --reverse --prompt "$1" --with-nth "$2" -d "\t"
            ;;
    esac
}

nine_anime_helper() {
    curl -s "$base_helper_url/$1?query=$2&apikey=saikou" | sed -nE "s@.*\"$3\":\"([^\"]*)\".*@\1@p"
}

download_images() {
    [ ! -d "$manga_dir/$title/chapter_$((progress + 1))" ] && mkdir -p "$manga_dir/$title/chapter_$((progress + 1))"
    send_notification "Downloading images" "" "" "$title - Chapter: $((progress + 1)) $chapter_title"
    printf "%s\n" "$1" | while read -r link; do
        number=$(printf "%03d" "$(printf "%s" "$link" | sed -nE "s@[a-zA-Z]([0-9]*)-.*@\1@p")")
        image_name=$(printf "%s.%s" "$number" "$(printf "%s" "$link" | sed -nE "s@.*\.(.*)@\1@p")")
        download_link=$(printf "%s/data/%s/%s" "$mangadex_data_base_url" "$mangadex_hash" "$link")
        curl -s "$download_link" -o "$manga_dir/$title/chapter_$((progress + 1))/$image_name" &
    done
    wait && sleep 2
}

download_thumbnails() {
    printf "%s\n" "$1" | while read -r cover_url media_id title; do
        curl -s -o "$images_cache_dir/  $title $media_id.jpg" "$cover_url" &
        if [ "$use_external_menu" = "1" ]; then
            entry=/tmp/jerry/applications/"$media_id.desktop"
            generate_desktop "$title" "$images_cache_dir/  $title $media_id.jpg" >"$entry" &
        fi
    done
    sleep "$2"
}

image_preview_fzf() {
    UB_PID_FILE="/tmp/.$(uuidgen)"
    if [ -z "$ueberzug_output" ]; then
        ueberzugpp layer --no-stdin --silent --use-escape-codes --pid-file "$UB_PID_FILE"
    else
        ueberzugpp layer -o "$ueberzug_output" --no-stdin --silent --use-escape-codes --pid-file "$UB_PID_FILE"
    fi
    UB_PID="$(cat "$UB_PID_FILE")"
    JERRY_UEBERZUG_SOCKET=/tmp/ueberzugpp-"$UB_PID".socket
    choice=$(find "$images_cache_dir" -type f -printf "%f\n" | fzf -i -q "$1" --cycle --preview-window="$preview_window_size" --preview="ueberzugpp cmd -s $JERRY_UEBERZUG_SOCKET -i fzfpreview -a add -x $ueberzug_x -y $ueberzug_y --max-width $ueberzug_max_width --max-height $ueberzug_max_height -f $images_cache_dir/{}" --reverse --with-nth 1..-2 -d " ")
    ueberzugpp cmd -s "$JERRY_UEBERZUG_SOCKET" -a exit
}

select_desktop_entry() {
    if [ "$use_external_menu" = "1" ]; then
        [ -n "$image_config_path" ] && choice=$(rofi -show drun -drun-categories jerry -filter "$1" -show-icons -theme "$image_config_path" | $sed -nE "s@.*/([0-9]*)\.desktop@\1@p") 2>/dev/null || choice=$(rofi -show drun -drun-categories jerry -filter "$1" -show-icons | $sed -nE "s@.*/([0-9]*)\.desktop@\1@p") 2>/dev/null
    else
        image_preview_fzf "$1"
    fi
}

#### ANILIST ANIME FUNCTIONS ####
get_anime_from_list() {
    anime_list=$(curl -s -X POST "$anilist_base" \
        -H 'Content-Type: application/json' \
        -H "Authorization: Bearer $access_token" \
        -d "{\"query\":\"query(\$userId:Int,\$userName:String,\$type:MediaType){MediaListCollection(userId:\$userId,userName:\$userName,type:\$type){lists{name isCustomList isCompletedList:isSplitCompletedList entries{...mediaListEntry}}user{id name avatar{large}mediaListOptions{scoreFormat rowOrder animeList{sectionOrder customLists splitCompletedSectionByFormat theme}mangaList{sectionOrder customLists splitCompletedSectionByFormat theme}}}}}fragment mediaListEntry on MediaList{id mediaId status score progress progressVolumes repeat priority private hiddenFromStatusLists customLists advancedScores notes updatedAt startedAt{year month day}completedAt{year month day}media{id title{userPreferred romaji english native}coverImage{extraLarge large}type format status(version:2)episodes volumes chapters averageScore popularity isAdult countryOfOrigin genres bannerImage startDate{year month day}}}\",\"variables\":{\"userId\":$user_id,\"type\":\"ANIME\"}}" |
        tr "\[\]" "\n" | $sed -nE "s@.*\"mediaId\":([0-9]*),\"status\":\"$1\",\"score\":(.*),\"progress\":([0-9]*),.*\"userPreferred\":\"([^\"]*)\".*\"coverImage\":\{\"extraLarge\":\"([^\"]*)\".*\"episodes\":([^,]*),.*@\5\t\1\t\4 \3|\6 episodes@p" | $sed 's/\\\//\//g;s/null/?/')
    if [ "$use_external_menu" = 1 ]; then
        case "$image_preview" in
            "true" | 1)
                download_thumbnails "$anime_list" "2"
                select_desktop_entry ""
                [ -z "$choice" ] && exit 1
                media_id=$(printf "%s" "$choice" | cut -d\  -f1)
                title=$(printf "%s" "$choice" | $sed -nE "s@$media_id (.*) [0-9?|]* episodes@\1@p")
                progress=$(printf "%s" "$choice" | $sed -nE "s@.* ([0-9]*)\|[0-9?]* episodes@\1@p")
                episodes_total=$(printf "%s" "$choice" | $sed -nE "s@.*\|([0-9?]*) episodes@\1@p")
                ;;
            *)
                tmp_anime_list=$(printf "%s" "$anime_list" | sed -nE "s@(.*\.[jpneg]*)[[:space:]]*([0-9]*)[[:space:]]*(.*)@\3\t\2\t\1@p")
                choice=$(printf "%s" "$tmp_anime_list" | launcher "Choose anime" "1")
                media_id=$(printf "%s" "$choice" | cut -f2)
                title=$(printf "%s" "$choice" | sed -nE "s@(.*) [0-9?|]* episodes.*@\1@p")
                progress=$(printf "%s" "$choice" | sed -nE "s@.* ([0-9]*)\|[0-9?]* episodes.*@\1@p")
                episodes_total=$(printf "%s" "$choice" | sed -nE "s@.*\|([0-9?]*) episodes.*@\1@p")
                ;;
        esac
    else
        case "$image_preview" in
            "true" | 1)
                download_thumbnails "$anime_list" "2"
                select_desktop_entry ""
                [ -z "$choice" ] && exit 0
                media_id=$(printf "%s" "$choice" | sed -nE "s@.* ([0-9]*)\.jpg@\1@p")
                title=$(printf "%s" "$choice" | $sed -nE "s@[[:space:]]*(.*) [0-9?|]* episodes.*@\1@p")
                progress=$(printf "%s" "$choice" | $sed -nE "s@.* ([0-9]*)\|[0-9?]* episodes.*@\1@p")
                episodes_total=$(printf "%s" "$choice" | $sed -nE "s@.*\|([0-9?]*) episodes.*@\1@p")
                ;;
            *)
                choice=$(printf "%s" "$anime_list" | launcher "Choose anime" "3")
                media_id=$(printf "%s" "$choice" | cut -f2)
                title=$(printf "%s" "$choice" | $sed -nE "s@.*$media_id\t(.*) [0-9?|]* episodes@\1@p")
                progress=$(printf "%s" "$choice" | $sed -nE "s@.* ([0-9]*)\|[0-9?]* episodes@\1@p")
                episodes_total=$(printf "%s" "$choice" | $sed -nE "s@.*\|([0-9?]*) episodes@\1@p")
                ;;
        esac
    fi
}

search_anime_anilist() {
    anime_list=$(curl -s -X POST "$anilist_base" \
        -H 'Content-Type: application/json' \
        -d "{\"query\":\"query(\$page:Int = 1 \$id:Int \$type:MediaType \$isAdult:Boolean = false \$search:String \$format:[MediaFormat]\$status:MediaStatus \$countryOfOrigin:CountryCode \$source:MediaSource \$season:MediaSeason \$seasonYear:Int \$year:String \$onList:Boolean \$yearLesser:FuzzyDateInt \$yearGreater:FuzzyDateInt \$episodeLesser:Int \$episodeGreater:Int \$durationLesser:Int \$durationGreater:Int \$chapterLesser:Int \$chapterGreater:Int \$volumeLesser:Int \$volumeGreater:Int \$licensedBy:[Int]\$isLicensed:Boolean \$genres:[String]\$excludedGenres:[String]\$tags:[String]\$excludedTags:[String]\$minimumTagRank:Int \$sort:[MediaSort]=[POPULARITY_DESC,SCORE_DESC]){Page(page:\$page,perPage:20){pageInfo{total perPage currentPage lastPage hasNextPage}media(id:\$id type:\$type season:\$season format_in:\$format status:\$status countryOfOrigin:\$countryOfOrigin source:\$source search:\$search onList:\$onList seasonYear:\$seasonYear startDate_like:\$year startDate_lesser:\$yearLesser startDate_greater:\$yearGreater episodes_lesser:\$episodeLesser episodes_greater:\$episodeGreater duration_lesser:\$durationLesser duration_greater:\$durationGreater chapters_lesser:\$chapterLesser chapters_greater:\$chapterGreater volumes_lesser:\$volumeLesser volumes_greater:\$volumeGreater licensedById_in:\$licensedBy isLicensed:\$isLicensed genre_in:\$genres genre_not_in:\$excludedGenres tag_in:\$tags tag_not_in:\$excludedTags minimumTagRank:\$minimumTagRank sort:\$sort isAdult:\$isAdult){id title{userPreferred}coverImage{extraLarge large color}startDate{year month day}endDate{year month day}bannerImage season seasonYear description type format status(version:2)episodes duration chapters volumes genres isAdult averageScore popularity nextAiringEpisode{airingAt timeUntilAiring episode}mediaListEntry{id status}studios(isMain:true){edges{isMain node{id name}}}}}}\",\"variables\":{\"page\":1,\"type\":\"ANIME\",\"sort\":\"SEARCH_MATCH\",\"search\":\"$1\"}}" |
        tr "\[\]" "\n" | sed -nE "s@.*\"id\":([0-9]*),.*\"userPreferred\":\"(.*)\"\},\"coverImage\":.*\"extraLarge\":\"([^\"]*)\".*\"episodes\":([^,]*),.*@\3\t\1\t\2 \4 episodes@p" | sed 's/\\\//\//g;s/null/?/')

    case "$image_preview" in
        "true" | "1")
            download_thumbnails "$anime_list" "2"
            select_desktop_entry ""
            [ -z "$choice" ] && exit 1
            media_id=$(printf "%s" "$choice" | cut -d\  -f1)
            title=$(printf "%s" "$choice" | $sed -nE "s@$media_id (.*) [0-9?]* episodes@\1@p")
            episodes_total=$(printf "%s" "$choice" | $sed -nE "s@.* ([0-9?]*) episodes@\1@p")
            ;;
        *)
            # TODO: implement this without image preview
            echo "TODO"
            ;;
    esac

    [ -z "$title" ] && exit 0
}

update_progress() {
    curl -s -X POST "$anilist_base" \
        -H 'Content-Type: application/json' \
        -H "Authorization: Bearer $access_token" \
        -d "{\"query\":\"mutation(\$id:Int \$mediaId:Int \$status:MediaListStatus \$score:Float \$progress:Int \$progressVolumes:Int \$repeat:Int \$private:Boolean \$notes:String \$customLists:[String]\$hiddenFromStatusLists:Boolean \$advancedScores:[Float]\$startedAt:FuzzyDateInput \$completedAt:FuzzyDateInput){SaveMediaListEntry(id:\$id mediaId:\$mediaId status:\$status score:\$score progress:\$progress progressVolumes:\$progressVolumes repeat:\$repeat private:\$private notes:\$notes customLists:\$customLists hiddenFromStatusLists:\$hiddenFromStatusLists advancedScores:\$advancedScores startedAt:\$startedAt completedAt:\$completedAt){id mediaId status score advancedScores progress progressVolumes repeat priority private hiddenFromStatusLists customLists notes updatedAt startedAt{year month day}completedAt{year month day}user{id name}media{id title{userPreferred}coverImage{large}type format status episodes volumes chapters averageScore popularity isAdult startDate{year}}}}\",\"variables\":{\"status\":\"$3\",\"progress\":$(($1 + 1)),\"mediaId\":$2}}"
    [ "$3" = "COMPLETED" ] && send_notification "Completed $anime_title" "5000"
    [ "$3" = "COMPLETED" ] && sed -i "/$media_id/d" "$history_file"
}

update_episode_from_list() {
    status_choice=$(printf "CURRENT\nCOMPLETED\nPAUSED\nDROPPED\nPLANNING" | launcher "Filter by status")
    get_anime_from_list "$status_choice"

    if [ -z "$title" ] || [ -z "$progress" ]; then
        exit 0
    fi

    send_notification "Current progress: $progress/$episodes_total episodes watched" "5000"

    if [ "$use_external_menu" = "0" ]; then
        new_episode_number=$(printf "Enter a new episode number: " && read -r new_episode_number)
    else
        new_episode_number=$(printf "" | launcher "Enter a new episode number")
    fi
    [ "$new_episode_number" -gt "$episodes_total" ] && new_episode_number=$episodes_total
    [ "$new_episode_number" -lt 0 ] && new_episode_number=0

    if [ -z "$new_episode_number" ]; then
        send_notification "No episode number given"
        exit 1
    fi

    send_notification "Updating progress for $title..."
    [ "$new_episode_number" -eq "$total" ] && status="COMPLETED" || status="CURRENT"
    response=$(update_progress "$((new_episode_number - 1))" "$media_id" "$status")
    send_notification "New progress: $new_episode_number/$episodes_total episodes watched"
    [ "$new_episode_number" -eq "$episodes_total" ] && send_notification "Completed $title"
}

#### ANILIST MANGA FUNCTIONS ####
get_manga_from_list() {
    manga_list=$(curl -s -X POST "$anilist_base" \
        -H 'Content-Type: application/json' \
        -H "Authorization: Bearer $access_token" \
        -d "{\"query\":\"query(\$userId:Int,\$userName:String,\$type:MediaType){MediaListCollection(userId:\$userId,userName:\$userName,type:\$type){lists{name isCustomList isCompletedList:isSplitCompletedList entries{...mediaListEntry}}user{id name avatar{large}mediaListOptions{scoreFormat rowOrder animeList{sectionOrder customLists splitCompletedSectionByFormat theme}mangaList{sectionOrder customLists splitCompletedSectionByFormat theme}}}}}fragment mediaListEntry on MediaList{id mediaId status score progress progressVolumes repeat priority private hiddenFromStatusLists customLists advancedScores notes updatedAt startedAt{year month day}completedAt{year month day}media{id title{userPreferred romaji english native}coverImage{extraLarge large}type format status(version:2)episodes volumes chapters averageScore popularity isAdult countryOfOrigin genres bannerImage startDate{year month day}}}\",\"variables\":{\"userId\":$user_id,\"type\":\"MANGA\"}}" |
        tr "\[|\]" "\n" | sed -nE "s@.*\"mediaId\":([0-9]*),\"status\":\"$1\",\"score\":(.*),\"progress\":([0-9]*),.*\"userPreferred\":\"([^\"]*)\".*\"coverImage\":\{\"extraLarge\":\"([^\"]*)\".*\"chapters\":([0-9]*).*@\5\t\1\t\4 \3|\6 chapters@p" | sed 's/\\\//\//g')
    case "$image_preview" in
        "true" | 1)
            download_thumbnails "$manga_list" "2"
            select_desktop_entry ""
            [ -z "$choice" ] && exit 1
            media_id=$(printf "%s" "$choice" | cut -d\  -f1)
            title=$(printf "%s" "$choice" | $sed -nE "s@$media_id (.*) [0-9|]* chapters@\1@p")
            progress=$(printf "%s" "$choice" | $sed -nE "s@.* ([0-9]*)\|[0-9]* chapters@\1@p")
            chapters_total=$(printf "%s" "$choice" | $sed -nE "s@.*\|([0-9]*) chapters@\1@p")
            ;;
        *)
            send_notification "Jerry" "" "" "TODO"
            ;;
    esac
}

#### ANIME SCRAPING FUNCTIONS ####
get_episode_info() {
    case "$provider" in
        zoro)
            zoro_id=$(curl -s "https://raw.githubusercontent.com/MALSync/MAL-Sync-Backup/master/data/anilist/anime/$media_id.json" | tr -d '\n' | $sed -nE "s@.*\"Zoro\":[[:space:]{]*\"([0-9]*)\".*@\1@p")
            episode_info=$(curl -s "https://zoro.to/ajax/v2/episode/list/$zoro_id" | $sed -e "s/</\n/g" -e "s/\\\\//g" | $sed -nE "s_.*a title=\"([^\"]*)\".*data-id=\"([0-9]*)\".*_\2\t\1_p" | $sed -n "$((progress + 1))p")
            ;;
        yugen)
            response=$(curl -s "https://yugenanime.tv/discover/?q=$(printf "%s" "$title" | tr ' ' '+')" | $sed -nE "s@.*href=\"/([^\"]*)/\" title=\"([^\"]*)\".*@\2\t\1@p")
            [ -z "$response" ] && exit 1
            # if it is only one line long, then auto select it
            if [ "$(printf "%s\n" "$response" | wc -l)" -eq 1 ]; then
                send_notification "Jerry" "" "" "Since there is only one result, it was automatically selected"
                choice=$response
            else
                choice=$(printf "%s" "$response" | launcher "Choose anime" 1)
            fi
            [ -z "$choice" ] && exit 1
            title=$(printf "%s" "$choice" | cut -f1)
            href=$(printf "%s" "$choice" | cut -f2)
            tmp_episode_info=$(curl -s "https://yugenanime.tv/$href/watch/" | $sed -nE "s@.*href=\"/([^\"]*)\" title=\"([^\"]*)\".*@\1\t\2@p" | $sed -n "$((progress + 1))p")
            tmp_href=$(printf "%s" "$tmp_episode_info" | cut -f1)
            ep_title=$(printf "%s" "$tmp_episode_info" | cut -f2)
            media_id=$(curl -s "https://yugenanime.tv/$tmp_href" | $sed -nE "s@.*id=\"main-embed\" src=\".*/e/([^/]*)/\".*@\1@p")
            episode_info=$(printf "%s\t%s" "$media_id" "$ep_title")
            ;;
        9anime)
            nineanime_href=$(curl -s "https://raw.githubusercontent.com/MALSync/MAL-Sync-Backup/master/data/anilist/anime/$media_id.json" | grep -o 'https://9anime[^"]*' | head -1)
            data_id=$(curl -s "$nineanime_href" | sed -nE "s@.*data-id=\"([0-9]*)\" data-url.*@\1@p")

            ep_list_vrf=$(nine_anime_helper "vrf" "$data_id" "url")
            episode_info=$(curl -sL "https://9anime.pl/ajax/episode/list/$data_id?vrf=$ep_list_vrf" | sed 's/<li/\n/g;s/\\//g' |
                sed -nE "s@.*data-ids=\"([^\"]*)\".*data-jp=\"[^\"]*\">([^<]*)<.*@\1\t\2@p" | sed -n "$((progress + 1))p")
            ;;
    esac
}

extract_from_json() {
    case "$provider" in
        zoro)
            encrypted=$(printf "%s" "$json_data" | tr "{}" "\n" | $sed -nE "s_.*\"file\":\"([^\"]*)\".*_\1_p" | grep "\.m3u8")
            if [ -n "$encrypted" ]; then
                video_link=$(printf "%s" "$json_data" | tr "{|}" "\n" | $sed -nE "s_.*\"file\":\"([^\"]*)\".*_\1_p" | head -1)
            else
                key="$(curl -s "https://github.com/enimax-anime/key/blob/e${embed_type}/key.txt" | $sed -nE "s_.*js-file-line\">(.*)<.*_\1_p")"
                encrypted_video_link=$(printf "%s" "$json_data" | tr "{|}" "\n" | $sed -nE "s_.*\"sources\":\"([^\"]*)\".*_\1_p" | head -1)
                # ty @CoolnsX for helping me with figuring out how to implement aes in openssl
                video_link=$(printf "%s" "$encrypted_video_link" | base64 -d |
                    openssl enc -aes-256-cbc -d -md md5 -k "$key" 2>/dev/null | $sed -nE "s_.*\"file\":\"([^\"]*)\".*_\1_p")
                json_data=$(printf "%s" "$json_data" | $sed -e "s|${encrypted_video_link}|${video_link}|")
            fi
            [ -n "$quality" ] && video_link=$(printf "%s" "$video_link" | $sed -e "s|/playlist.m3u8|/$quality/index.m3u8|")

            if [ "$json_output" = "1" ]; then
                printf "%s\n" "$json_data"
                exit 0
            fi
            subs_links=$(printf "%s" "$json_data" | tr "{}" "\n" | $sed -nE "s@\"file\":\"([^\"]*)\",\"label\":\"(.$subs_language)[,\"\ ].*@\1@p")
            subs_arg="--sub-file"
            num_subs=$(printf "%s" "$subs_links" | wc -l)
            if [ "$num_subs" -gt 0 ]; then
                subs_links=$(printf "%s" "$subs_links" | $sed -e "s/:/\\$path_thing:/g" -e "H;1h;\$!d;x;y/\n/$separator/" -e "s/$separator\$//")
                subs_arg="--sub-files=$subs_links"
            fi
            [ -z "$subs_links" ] && send_notification "No subtitles found"
            ;;
        yugen)
            if [ "$json_output" = "1" ]; then
                printf "%s\n" "$json_data"
                exit 0
            fi
            hls_link_1=$(printf "%s" "$json_data" | tr '{}' '\n' | $sed -nE "s@.*\"hls\": \[\"([^\"]*)\".*@\1@p")
            # hls_link_2=$(printf "%s" "$json_data" | tr '{}' '\n' | $sed -nE "s@.*hls.*, \"([^\"]*)\".\]*@\1@p")
            # gogo_link=$(printf "%s" "$json_data" | tr '{}' '\n' | $sed -nE "s@.*\"src\": \"([^\"]*)\", \"type\": \"embed.*@\1@p")
            if [ -n "$quality" ]; then
                video_link=$(printf "%s" "$hls_link_1" | $sed -e "s/\.m3u8$/\.$quality.m3u8/")
            else
                video_link=$hls_link_1
            fi
            ;;
        9anime)
            if [ "$json_output" = "1" ]; then
                printf "%s\n" "$json_data"
                exit 0
            fi
            case "$video_provider" in
                "Vidstream")
                    video_link="$(printf "%s" "$json_data" | sed -nE "s@.*file\":\"([^\"]*\.mp4)\".*@\1@p")"
                    case "$quality" in
                        1080) video_link="$(printf "%s" "$video_link" | sed "s@/br/list\.m3u8@/br/H4/v\.m3u8@")" ;;
                        720) video_link="$(printf "%s" "$video_link" | sed "s@/br/list\.m3u8@/br/H3/v\.m3u8@")" ;;
                        480) video_link="$(printf "%s" "$video_link" | sed "s@/br/list\.m3u8@/br/H2/v\.m3u8@")" ;;
                        360) video_link="$(printf "%s" "$video_link" | sed "s@/br/list\.m3u8@/br/H1/v\.m3u8@")" ;;
                    esac
                    ;;
                "MyCloud")
                    video_link="$(printf "%s" "$json_data" | sed -nE "s@.*file\":\"([^\"]*\.m3u8)\".*@\1@p")"
                    ;;
            esac
            ;;
    esac
    [ "$((progress + 1))" -eq "$episodes_total" ] && status="COMPLETED" || status="CURRENT"
}

get_json() {
    case "$provider" in
        zoro)
            source_id=$(curl -s "https://zoro.to/ajax/v2/episode/servers?episodeId=$episode_id" | tr "<|>" "\n" | $sed -nE 's_.*data-id=\\"([^"]*)\\".*_\1_p' | head -1)
            embed_link=$(curl -s "https://zoro.to/ajax/v2/episode/sources?id=$source_id" | $sed -nE "s_.*\"link\":\"([^\"]*)\".*_\1_p")

            # get the juicy links
            parse_embed=$(printf "%s" "$embed_link" | $sed -nE "s_(.*)/embed-(4|6)/(.*)\?k=1\$_\1\t\2\t\3_p")
            provider_link=$(printf "%s" "$parse_embed" | cut -f1)
            source_id=$(printf "%s" "$parse_embed" | cut -f3)
            embed_type=$(printf "%s" "$parse_embed" | cut -f2)

            json_data=$(curl -s "${provider_link}/ajax/embed-${embed_type}/getSources?id=${source_id}" -H "X-Requested-With: XMLHttpRequest")
            ;;
        yugen)
            json_data=$(curl -s 'https://yugenanime.tv/api/embed/' -X POST -H 'X-Requested-With: XMLHttpRequest' --data-raw "id=$episode_id&ac=0")
            ;;
        9anime)
            server_list_vrf=$(nine_anime_helper "vrf" "$episode_id" "url")

            # change head to tail to get dub
            provider_id=$(curl -sL "https://9anime.pl/ajax/server/list/$episode_id?vrf=$server_list_vrf" | sed "s/</\n/g;s/\\\//g" | sed -nE "s@.*data-link-id=\"([^\"]*)\">$video_provider.*@\1@p" | head -1)
            provider_vrf=$(nine_anime_helper "vrf" "$provider_id" "url")

            encrypted_provider_url=$(curl -sL "https://9anime.pl/ajax/server/$provider_id?vrf=$provider_vrf" | sed "s/\\\//g" | sed -nE "s@.*\{\"url\":\"([^\"]*)\".*@\1@p")
            provider_embed=$(nine_anime_helper "decrypt" "$encrypted_provider_url" "url")
            provider_query=$(printf "%s" "$provider_embed" | sed -nE "s@.*/e/(.*)@\1@p")

            case "$video_provider" in
                "Vidstream")
                    raw_url=$(nine_anime_helper "rawvizcloud" "$provider_query" "rawURL")
                    json_data=$(curl -s "$raw_url" -e "$provider_embed" | sed "s/\\\//g")
                    ;;
                "MyCloud")
                    raw_url=$(nine_anime_helper "rawmcloud" "$provider_query" "rawURL")
                    json_data=$(curl -s "$raw_url" -e "$provider_embed" | sed "s/\\\//g")
                    ;;
                    # "Mp4upload")
                    #     video_link=$(curl -s "$provider_embed" | sed -nE "s@.*src: \"([^\"]*)\".*@\1@p")
                    #     ;;
            esac
            ;;
    esac

    [ -n "$json_data" ] && extract_from_json
}

#### MANGA SCRAPING FUNCTIONS ####
get_chapter_info() {
    manga_provider="mangadex"
    case "$manga_provider" in
        mangadex)
            mangadex_id=$(curl -s "https://raw.githubusercontent.com/MALSync/MAL-Sync-Backup/master/data/anilist/manga/$media_id.json" | tr -d "\n" | sed -nE "s@.*\"Mangadex\":[[:space:]{]*\"([^\"]*)\".*@\1@p")
            chapter_info=$(curl -s "https://api.mangadex.org/manga/$mangadex_id/feed?limit=164&translatedLanguage[]=en" | sed "s/}]},/\n/g" |
                sed -nE "s@.*\"id\":\"([^\"]*)\".*\"chapter\":\"$((progress + 1))\",\"title\":\"([^\"]*)\".*@\1\t\2@p")
            ;;
    esac
}

get_manga_json() {
    case "$manga_provider" in
        mangadex)
            json_data=$(curl -s "https://api.mangadex.org/at-home/server/$chapter_id" | sed "s/\\\//g")
            if [ "$json_output" = "1" ]; then
                printf "%s\n" "$json_data"
                exit 0
            fi
            mangadex_data_base_url=$(printf "%s" "$json_data" | sed -nE "s@.*\"baseUrl\":\"([^\"]*)\".*@\1@p")
            mangadex_hash=$(printf "%s" "$json_data" | sed -nE "s@.*\"hash\":\"([^\"]*)\".*@\1@p")
            image_links=$(printf "%s" "$json_data" | sed -nE "s@.*data\":\[(.*)\],.*@\1@p" | sed "s/,/\n/g;s/\"//g")
            download_images "$image_links"
            ;;
    esac
}

#### MEDIA FUNCTIONS ####
play_video() {
    case "$provider" in
        zoro)
            displayed_episode_title="Ep $((progress + 1)) $episode_title"
            ;;
        yugen)
            displayed_episode_title="Ep $episode_title"
            ;;
        9anime)
            displayed_episode_title="Ep $((progress + 1)) $episode_title"
            ;;
    esac
    displayed_title="$title - $displayed_episode_title"
    case $player in
        mpv)
            [ -f "$history_file" ] && history=$(grep -E "^${media_id}[[:space:]]*$((progress + 1))" "$history_file")
            [ -n "$history" ] && resume_from=$(printf "%s" "$history" | cut -f3)
            if [ -n "$resume_from" ]; then
                opts="--start=${resume_from}"
                send_notification "Resuming from" "" "" "$resume_from"
            else
                opts=""
            fi
            if [ -n "$subs_links" ]; then
                send_notification "$title" "4000" "$images_cache_dir/  $title $progress|$episodes_total episodes $media_id.jpg" "$displayed_episode_title"
                mpv "$video_link" "$opts" "$subs_arg" "$subs_links" --force-media-title="$displayed_title" 2>&1 | tee $tmp_position
            else
                send_notification "$title" "4000" "$images_cache_dir/  $title $progress|$episodes_total episodes $media_id.jpg" "$displayed_episode_title"
                mpv "$video_link" "$opts" --force-media-title="$displayed_title" 2>&1 | tee $tmp_position
            fi
            stopped_at=$(cat $tmp_position | $sed -nE "s@.*AV: ([0-9:]*) / ([0-9:]*) \(([0-9]*)%\).*@\1@p" | tail -1)
            percentage_progress=$(cat $tmp_position | $sed -nE "s@.*AV: ([0-9:]*) / ([0-9:]*) \(([0-9]*)%\).*@\3@p" | tail -1)
            if [ "$percentage_progress" -gt 85 ]; then
                response=$(update_progress "$progress" "$media_id" "$status")
                if printf "%s" "$response" | grep -q "errors"; then
                    send_notification "Error" "" "" "Could not update progress"
                else
                    send_notification "Updated progress to $((progress + 1))/$episodes_total episodes watched"
                    [ -n "$history" ] && $sed -i "/^$media_id/d" "$history_file"
                fi
            else
                send_notification "Current progress" "" "" "$progress/$episodes_total episodes watched"
                send_notification "Your progress has not been updated"
                printf "%s\t%s\t%s" "$media_id" "$((progress + 1))" "$stopped_at" >>"$history_file.tmp"
                mv "$history_file.tmp" "$history_file"
                send_notification "Stopped at: $stopped_at" "5000"
            fi
            ;;
    esac
}

read_chapter() {
    swayimg "$manga_dir/$title/chapter_$((progress + 1))"/*
}

watch_anime() {

    get_episode_info

    if [ -z "$episode_info" ]; then
        send_notification "Error" "" "" "$title not found"
        exit 1
    fi
    episode_id=$(printf "%s" "$episode_info" | cut -f1)
    episode_title=$(printf "%s" "$episode_info" | cut -f2)

    get_json
    [ -z "$video_link" ] && exit 1
    play_video

}

read_manga() {

    get_chapter_info
    if [ -z "$chapter_info" ]; then
        send_notification "Error" "" "" "$title not found"
        exit 1
    fi
    chapter_id=$(printf "%s" "$chapter_info" | cut -f1)
    chapter_title=$(printf "%s" "$chapter_info" | cut -f2)

    get_manga_json
    read_chapter

}

watch_anime_choice() {
    [ -z "$media_id" ] && get_anime_from_list "CURRENT"
    if [ -z "$media_id" ] || [ -z "$title" ] || [ -z "$progress" ] || [ -z "$episodes_total" ]; then
        send_notification "Jerry" "" "" "Error, no anime found"
        exit 1
    fi
    send_notification "Loading" "3000" "$images_cache_dir/  $title $progress|$episodes_total episodes $media_id.jpg" "$title"
    watch_anime
}

read_manga_choice() {
    [ -z "$media_id" ] && get_manga_from_list "CURRENT"
    if [ -z "$media_id" ] || [ -z "$title" ] || [ -z "$progress" ] || [ -z "$chapters_total" ]; then
        send_notification "Jerry" "" "" "Error, no manga found"
        exit 1
    fi
    send_notification "Loading" "" "" "$title"
    read_manga
}

main() {
    check_credentials
    [ -n "$query" ] && choice="Watch New Anime"
    [ -z "$choice" ] && choice=$(printf "Watch Anime\nRead Manga\nBinge Watch Anime\nBinge Read Manga\nUpdate (Episodes, Status, Score)\nInfo\nWatch New Anime\nRead New Manga" | launcher "Choose an option: ")
    case "$choice" in
        "Watch Anime") watch_anime_choice && exit 0 ;;
        "Read Manga") read_manga_choice && exit 0 ;;
        "Watch New Anime")
            [ -z "$query" ] && get_input "Search anime: "
            [ -z "$query" ] && exit 1
            search_anime_anilist "$query"
            [ -z "$progress" ] && progress=0
            [ "$json_output" = true ] || send_notification "Disclaimer" "5000" "" "You need to complete the 1st episode to update your progress"
            watch_anime
            ;;
        "Update (Episodes, Status, Score)")
            update_choice=$(printf "Change Episodes Watched\nChange Chapters Read\nChange Status\nChange Score" | launcher "Choose an option: ")
            case "$update_choice" in
                "Change Episodes Watched") update_episode_from_list "ANIME" ;;
                "Change Chapters Read") update_episode_from_list "MANGA" ;;
                "Change Status")
                    media_type=$(printf "ANIME\nMANGA" | launcher "Choose a media type")
                    [ -z "$media_type" ] && exit 0
                    update_status "$media_type"
                    ;;
                "Change Score")
                    media_type=$(printf "ANIME\nMANGA" | launcher "Choose a media type")
                    [ -z "$media_type" ] && exit 0
                    update_score "$media_type"
                    ;;
            esac
            ;;
    esac
}

configuration
query=""
while [ $# -gt 0 ]; do
    case "$1" in
        --)
            shift
            query="$*"
            break
            ;;
        -h | --help)
            usage && exit 0
            ;;
        -i | --image-preview)
            image_preview="1"
            shift
            ;;
        -j | --json)
            json_output="1"
            shift
            ;;
        -l | --language)
            subs_language="$2"
            if [ -z "$subs_language" ]; then
                subs_language="english"
                shift
            else
                if [ "${subs_language#-}" != "$subs_language" ]; then
                    subs_language="english"
                    shift
                else
                    subs_language="$(echo "$subs_language" | cut -c2-)"
                    shift 2
                fi
            fi
            ;;
        --rofi | --dmenu | --external-menu)
            use_external_menu="1"
            shift
            ;;
        -q | --quality)
            quality="$2"
            if [ -z "$quality" ]; then
                quality="1080"
                shift
            else
                if [ "${quality#-}" != "$quality" ]; then
                    quality="1080"
                    shift
                else
                    shift 2
                fi
            fi
            ;;
        -s | --syncplay)
            player="syncplay"
            shift
            ;;
        -u | -U | --update)
            update_script
            ;;
        -v | -V | --version)
            send_notification "Jerry Version: $JERRY_VERSION" && exit 0
            ;;
        *)
            if [ "${1#-}" != "$1" ]; then
                query="$query $1"
            else
                query="$query $1"
            fi
            shift
            ;;
    esac
done
query="$(printf "%s" "$query" | tr ' ' '-' | sed "s/^-//g")"
if [ "$image_preview" = 1 ]; then
    test -d "$images_cache_dir" || mkdir -p "$images_cache_dir"
    if [ "$use_external_menu" = 1 ]; then
        mkdir -p "/tmp/jerry/applications/"
        [ ! -L "$applications" ] && ln -sf "/tmp/jerry/applications/" "$applications"
    fi
fi

main
