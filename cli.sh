#!/usr/bin/env bash
# Simple script to download videos from GetCourse.ru
# on Linux/*BSD
# Dependencies: bash, coreutils, curl, grep

set -eu
set +f
set -o pipefail

if [ ! -f "$0" ]
then
    a0="$0"
else
    a0="bash $0"
fi

_echo_help(){
    echo "
Скрипт для скачивания видео с GetCourse.ru

Можно использовать три способа запуска:

1. С позиционными аргументами:
   $a0 \"ссылка_на_плейлист\" \"путь_к_файлу.ts\"

2. С именованными параметрами:
   $a0 -u \"ссылка_на_плейлист\" -f \"путь_к_файлу.ts\"
   или
   $a0 --url=\"ссылка_на_плейлист\" --file=\"путь_к_файлу.ts\"

3. Без параметров - скрипт запросит ввод URL и путь к файлу поэтапно:
   $a0

Первым аргументом должна быть ссылка на плей-лист, найденная в исходном коде страницы сайта GetCourse.
Пример: <video id=\"vgc-player_html5_api\" data-master=\"нужная ссылка\" ... />.
Вторым аргументом должен быть путь к файлу для сохранения скачанного видео, рекомендуемое расширение — ts.
Пример: \"Как скачать видео с GetCourse.ts\"

Инструкция с графическими иллюстрациями здесь: https://github.com/mikhailnov/getcourse-video-downloader
О проблемах в работе сообщайте сюда: https://github.com/mikhailnov/getcourse-video-downloader/issues
"
}

# Инициализация переменных
URL=""
result_file=""

# Функция для обработки параметров командной строки
parse_params() {
    # Проверка на наличие флагов -u, -f, --url, --file
    while [ $# -gt 0 ]; do
        case "$1" in
            -u|--url)
                if [ -n "$2" ] && [ "${2:0:1}" != "-" ]; then
                    URL="$2"
                    shift 2
                else
                    echo "Ошибка: Отсутствует аргумент для параметра $1" >&2
                    _echo_help
                    exit 1
                fi
                ;;
            --url=*)
                URL="${1#*=}"
                shift
                ;;
            -f|--file)
                if [ -n "$2" ] && [ "${2:0:1}" != "-" ]; then
                    result_file="$2"
                    shift 2
                else
                    echo "Ошибка: Отсутствует аргумент для параметра $1" >&2
                    _echo_help
                    exit 1
                fi
                ;;
            --file=*)
                result_file="${1#*=}"
                shift
                ;;
            -h|--help)
                _echo_help
                exit 0
                ;;
            *)
                # Если нет явных флагов, и параметры не заданы, считаем их позиционными
                if [ -z "$URL" ] && [ -z "$result_file" ] && [ $# -eq 2 ]; then
                    URL="$1"
                    result_file="$2"
                    shift 2
                else
                    shift
                fi
                ;;
        esac
    done
}

# Функция для интерактивного ввода параметров
prompt_for_input() {
    # Запрашиваем URL, если он не был предоставлен
    if [ -z "$URL" ]; then
        echo "Введите ссылку на плейлист GetCourse (найденную в исходном коде страницы):"
        read -r URL
        # Проверка, что URL не пустой
        while [ -z "$URL" ]; do
            echo "URL не может быть пустым. Пожалуйста, введите ссылку:"
            read -r URL
        done
    fi
    
    # Запрашиваем путь к файлу результата, если он не был предоставлен
    if [ -z "$result_file" ]; then
        echo "Введите путь к файлу для сохранения видео (рекомендуемое расширение - .ts):"
        read -r result_file
        # Проверка, что путь к файлу не пустой
        while [ -z "$result_file" ]; do
            echo "Путь к файлу не может быть пустым. Пожалуйста, введите путь к файлу:"
            read -r result_file
        done
    fi
}

tmpdir="$(umask 077 && mktemp -d)"
export TMPDIR="$tmpdir"
trap 'rm -fr "$tmpdir"' EXIT

# Обработка параметров
parse_params "$@"

# Если параметры не предоставлены через командную строку, запрашиваем их интерактивно
if [ -z "$URL" ] || [ -z "$result_file" ]; then
    prompt_for_input
fi

touch "$result_file"

echo "Используемые параметры:"
echo "URL: $URL"
echo "Файл для сохранения: $result_file"
echo "Начинаю загрузку..."

main_playlist="$(mktemp)"
curl -L --output "$main_playlist" "$URL"
second_playlist="$(mktemp)"
# Бывает (я встречал) 2 варианта видео
# Может быть, можно проверять [[ "$URL" =~ .*".m3u8".* ]]
# *.bin то же самое, что *.ts
if grep -qE '^https?:\/\/.*\.(ts|bin)' "$main_playlist" 2>/dev/null
then
    # В плей-листе перечислены напрямую ссылки на фрагменты видео
    # (если запустили проигрывание, зашли в инструменты разработчика Chromium -> Network,
    # нашли файл m3u8 и скопировали ссылку на него)
    cp "$main_playlist" "$second_playlist"
else
    # В плей-листе перечислены ссылки на плей-листы частей видео а разных разрешениях,
    # последним идет самое большое разрешение, его и скачиваем
    tail="$(tail -n1 "$main_playlist")"
    if ! [[ "$tail" =~ ^https?:// ]]; then
        echo "В содержимом заданной ссылки нет прямых ссылок на файлы *.bin (*.ts) (первый вариант),"
        echo "также последняя строка в ней не содержит ссылки на другой плей-лист (второй вариант)."
        echo "Либо указана неправильная ссылка, либо GetCourse изменил алгоритмы."
        echo "Если уверены, что дело в изменившихся алгоритмах GetCourse, опишите проблему здесь:"
        echo "https://github.com/mikhailnov/getcourse-video-downloader/issues (на русском)."
        exit 1
    fi
    curl -L --output "$second_playlist" "$tail"
fi

c=0
while read -r line
do
    if ! [[ "$line" =~ ^http ]]; then continue; fi
    echo "Загрузка фрагмента $(($c+1))..."
    curl --retry 12 -L --output "${tmpdir}/$(printf '%05d' "$c").ts" "$line"
    c=$((++c))
done < "$second_playlist"

echo "Объединение фрагментов в итоговый файл..."
cat "$tmpdir"/*.ts > "$result_file"
echo "Скачивание завершено. Результат здесь:
$result_file"