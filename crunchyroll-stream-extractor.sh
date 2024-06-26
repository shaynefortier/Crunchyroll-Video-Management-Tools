#!/bin/bash

# --------------------------------------------------
# DESCRIPTION
# --------------------------------------------------
#
# Extracts streams from MKV videos generated by crunchy-cli or crunchyroll-downloader.
# Every audio and subtitles languages will be seperated into their own single files.
# It operates in bulk for files in the operating directory
#
# --------------------------------------------------
# INSTRUCTION
# --------------------------------------------------
#
# Usage: ./crunchyroll-stream-extracter
#
# --------------------------------------------------
#
# Dependencies
# - ffmpeg https://ffmpeg.org
# - ffprobe https://ffmpeg.org
# - jq
#
# --------------------------------------------------

# Prepare Default Data
declare -A AUDIO_FILENAME=( [ar-ME]=.me-dub [ar-SA]=.sa-dub [de-DE]=.de-dub [en-IN]=.in-dub [en-US]=.dub [es-419]=.419-dub [es-ES]=.es-dub [es-LA]=.la-dub [fr-FR]=.vf [hi-IN]=.hi-dub [it-IT]=.it-dub [ja-JP]='' [pt-BR]=.br-dub [pt-PT]=.pt-dub [ru-RU]=.ru-dub [zh-CN]=.zh-dub )
IS_MOVIE=false
IGNORE_AUDIO=()

shopt -s nullglob
SEASONS_DIR=('Season '*/)
shopt -u nullglob


    # Validates the presence of season directories or video files in the current directory.
    # 
    # This function checks if there are any directories starting with "Season" in the `SEASONS_DIR` array. 
    # If there are directories, it prints "Season directories found". If there are no directories, it checks
    # if there are any video files with the extension ".mkv" in the current directory. If there are video files,
    # it sets the `IS_MOVIE` variable to `true` and prints "We found video file in the current directory".
    # If there are no video files, it prints "There is no video to work on" and exits the script.
    # 
    # Parameters:
    #   None
    # 
    # Returns:
    #   None
validate(){
    echo ${#SEASONS_DIR[@]}
    if [ ${#SEASONS_DIR[@]} -gt 0 ]; then
        echo "Season directories found"
    else
        local files_in_current_directory=$(find . -maxdepth 1 -type f -name "*.mkv" | wc -l)
        echo "There is no directory starting with 'Season'. Let's check if there are files in the current directory"
        if [ $files_in_current_directory -gt 0 ]; then
            IS_MOVIE=true
            echo 'We found video file in the current directory'
        else
            echo "There is no video to work on"
            exit
        fi
    fi
}

    # Probe file
    # 
    # This function probes the given MKV file using ffprobe and saves the output to .csx-entry.json.
    # 
    # Parameters:
    #   $1 (required): The path to the MKV file to probe.
    # 
    # Returns:
    #   None
probe(){
    # $1 represents the mkv file
    ffprobe -loglevel quiet -print_format json -show_entries stream=index,codec_type:stream_tags=language,title "$1" > .csx-entry.json
}

    # Extracts videos from an MKV file.
    #
    # This function takes an MKV file as input and extracts all the video streams from it.
    # It first counts the number of video streams in the file using the `grep` command and stores the result in the `vid_stream_nb` variable.
    # Then, it uses the `pcregrep` command to find the indexes of all the video streams in the file and stores them in the `vid_indexes` array.
    # The video stream indexes are extracted using regular expressions and the `sed` command.
    #
    # The function then reads the contents of the `.csx-entry.json` file into the `csx_entry` variable using the `cat` command.
    #
    # Next, it iterates over each video stream index in the `vid_indexes` array.
    # If the index is 0, it sets the `audio_index` variable to the value of `vid_stream_nb` and adds it to the `IGNORE_AUDIO` array.
    # If the index is not 0, it extracts the video title using regular expressions and the `pcregrep` command.
    # It then finds the audio stream index associated with the video stream using regular expressions and the `pcregrep` command.
    # The audio stream index is extracted using regular expressions and the `sed` command.
    # The audio stream index is added to the `IGNORE_AUDIO` array.
    #
    # Finally, the function extracts the audio stream associated with the video stream using the `ffmpeg` command.
    # The extracted audio stream is saved in an MP4 file with a filename based on the original MKV file name and the audio language.
    #
    # Parameters:
    #   $1 (required): The path to the MKV file.
    #
    # Returns:
    #   None
extract_videos(){
    # $1 represents the mkv file
    local vid_stream_nb=$(jq '.streams | map(select(.codec_type == "video")) | length' .csx-entry.json)
    local vid_indexes=( $(jq -r '.streams[] | select(.codec_type == "video") | .index' .csx-entry.json) )

    # Read the .csx-entry.json file into a variable
    local csx_entry=$(cat .csx-entry.json)

    for i in "${vid_indexes[@]}"; do
        local audio_index
        if [ $i -eq 0 ]; then
            audio_index=$vid_stream_nb
            IGNORE_AUDIO=($audio_index)
        else
            local video_title=$(jq -r '.streams[] | select(.codec_type == "video" and .index == '${i}') | .tags.title' .csx-entry.json)
            local audio_index=$(jq -r '.streams[] | select(.codec_type == "audio" and (.tags.title | test("\\[Video: '"${video_title}"'\\]"))) | .index' .csx-entry.json)
            IGNORE_AUDIO=(${IGNORE_AUDIO[@]} $audio_index)
        fi
        local lang=$(jq -r '.streams[] | select(.codec_type == "audio" and .index == '${audio_index}') | .tags.language' .csx-entry.json)
        echo "Ignored audio: "${IGNORE_AUDIO[@]}
        ffmpeg -i "$1" -map 0:${i} -map 0:${audio_index} -c copy "${1%.mkv}${AUDIO_FILENAME[$lang]}.mp4"
    done
}

    # Extracts audio streams from an mkv file and saves them as aac files.
    #
    # Parameters:
    #   $1 (required): The path to the mkv file.
    #
    # Returns:
    #   None
extract_audios(){
    # $1 represents the mkv file
    local all_audio_indexes=( $(jq -r '.streams[] | select(.codec_type == "audio") | .index' .csx-entry.json) )
    local audio_indexes=()
    for index in "${all_audio_indexes[@]}"; do
        if [[ ! " ${IGNORE_AUDIO[@]} " =~ " ${index} " ]]; then
            audio_indexes+=("$index")
        fi
    done

    # Read the .csx-entry.json file into a variable
    local csx_entry=$(cat .csx-entry.json)

    for i in "${audio_indexes[@]}"; do
        local lang=$(jq -r '.streams[] | select(.index == '${i}' and .codec_type == "audio") | .tags.language' .csx-entry.json)
        ffmpeg -i "$1" -map 0:${i} -c copy "${1%.mkv}${AUDIO_FILENAME[$lang]}.aac"
    done
}

    # Extracts subtitles from an mkv file and saves them as separate subtitle files.
    #
    # Parameters:
    #   $1 (required): The path to the mkv file.
    #
    # Returns:
    #   None.
extract_subtitles(){
    # $1 represents the mkv file
    local subtitle_indexes=( $(jq -r '.streams[] | select(.codec_type == "subtitle") | .index' .csx-entry.json) )

    # Read the .csx-entry.json file into a variable
    local csx_entry=$(cat .csx-entry.json)

    for i in "${subtitle_indexes[@]}"; do
        local sub_lang=$(jq -r '.streams[] | select(.index == '${i}' and .codec_type == "subtitle") | .tags.language' .csx-entry.json)
        local sub_title=$(jq -r '.streams[] | select(.index == '${i}' and .codec_type == "subtitle") | .tags.title' .csx-entry.json)

        if grep -q "\(CC\)" <<< "$sub_title" ; then
            ffmpeg -i "$1" -map 0:${i} -c copy "${1%.mkv}${AUDIO_FILENAME[$sub_lang]}.${sub_lang}.ass"
        else
            ffmpeg -i "$1" -map 0:${i} -c copy "${1%.mkv}.${sub_lang}.ass"
        fi
    done
}

    # Extracts video files from season directories or the current directory and processes them.
    #
    # This function initializes an empty array to hold the list of files to be processed.
    # If the script is processing a series, it adds all the video files from all season directories to the array.
    # If the script is processing a movie, it adds all video files in the current directory to the array.
    # The function then iterates over each file in the array and performs the following actions:
    #   - Prints the name of the file being processed.
    #   - Resets the IGNORE_AUDIO array.
    #   - Calls the probe function to probe the file.
    #   - Calls the extract_videos function to extract videos from the file.
    #   - Calls the extract_audios function to extract audios from the file.
    #   - Calls the extract_subtitles function to extract subtitles from the file.
    # Finally, it removes the .csx-entry.json file.
    #
    # Parameters:
    #   None
    #
    # Returns:
    #   None
extract(){
    # Define an empty array to hold the list of files
    local files=()

    # If it's a series, add all the video files from all season directories to the array
    if [ "$IS_MOVIE" = false ]; then
        for dir in "${SEASONS_DIR[@]}"; do
            files+=("$dir"*.mkv)
        done
    else
        # If it's a movie, add all video files in the current directory to the array
        files=(*.mkv)
    fi

    # Now we can handle all files uniformly, irrespective of whether they're part of a series or a movie
    for file in "${files[@]}"; do
        echo "Processing $file"
        IGNORE_AUDIO=()  # Assuming this array needs to be reset for every file
        probe "$file"
        extract_videos "$file"
        extract_audios "$file"
        extract_subtitles "$file"
    done

    # The cleanup part
    rm .csx-entry.json
}

    # Cleanup function to handle the extraction process completion and optionally delete the original MKV files.
    #
    # This function prints a message indicating that the extraction process is complete.
    # It then prompts the user with a question to delete the original MKV files.
    # If the user responds with "y" or "Y", it checks if the script is processing a movie or a series.
    # If it's a series, it iterates over each season directory and deletes all MKV files.
    # If it's a movie, it deletes all MKV files in the current directory.
    # Finally, it prints a message indicating whether the MKV files have been deleted or kept.
    #
    # Parameters:
    #   None
    #
    # Returns:
    #   None
cleanup(){
    echo "The extraction process is complete."
    read -p "Do you want to delete the original MKV files? [y/N]: " response
    if [[ $response =~ ^([yY][eE][sS]|[yY])$ ]]
    then
        if [ "$IS_MOVIE" = false ]; then
            for dir in "${SEASONS_DIR[@]}"; do
                rm "${dir}"*.mkv
            done
        else
            rm *.mkv
        fi
        echo "All MKV files have been deleted."
    else
        echo "The MKV files have been kept."
    fi
}

validate
extract
cleanup
