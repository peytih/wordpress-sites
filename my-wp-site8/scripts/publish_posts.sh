#!/bin/bash

# Настройки
WP_CONTAINER="my-wp-site8"
ACTION=$1
CATEGORY_NAME=$2
POST_COUNT=$3

show_usage() {
  echo " Использование: ./manage_category_posts.sh <action> <category> [count]"
  echo ""
  echo "Доступные действия:"
  echo "  publish    - Опубликовать черновики категории"
  echo "  hide       - Скрыть опубликованные посты (перевести в черновики)"
  echo "  schedule   - Запланировать публикацию на завтра"
  echo "  list       - Показать посты категории"
  echo "  count      - Показать статистику"
  echo "  preview    - Показать какие посты будут опубликованы"
  echo ""
  echo "Параметры:"
  echo "  count      - Количество постов (опционально)"
  echo ""
  echo "Примеры:"
  echo "  ./manage_category_posts.sh publish test1          # Опубликовать ВСЕ посты test1"
  echo "  ./manage_category_posts.sh publish test1 3        # Опубликовать 3 поста из test1"
  echo "  ./manage_category_posts.sh publish test1 1        # Опубликовать 1 пост из test1"
  echo "  ./manage_category_posts.sh preview test1 5        # Показать первые 5 постов"
  echo "  ./manage_category_posts.sh schedule test1 2       # Запланировать 2 поста на завтра"
  echo ""
  echo " Доступные категории:"
  docker exec $WP_CONTAINER wp --allow-root term list category --field=name --format=csv
}

if [ -z "$ACTION" ] || [ -z "$CATEGORY_NAME" ]; then
  show_usage
  exit 1
fi

# Функция для получения постов с ограничением по количеству
get_posts() {
  local status=$1
  local category=$2
  local limit=$3
  
  if [ -n "$limit" ] && [ "$limit" -gt 0 ]; then
    docker exec $WP_CONTAINER wp --allow-root post list \
      --post_type=post \
      --post_status="$status" \
      --category_name="$category" \
      --orderby=date \
      --order=asc \
      --posts_per_page="$limit" \
      --field=ID
  else
    docker exec $WP_CONTAINER wp --allow-root post list \
      --post_type=post \
      --post_status="$status" \
      --category_name="$category" \
      --orderby=date \
      --order=asc \
      --field=ID
  fi
}

# Функция для показа preview постов
show_preview() {
  local category=$1
  local limit=$2
  local status="draft"
  
  echo " ПРЕВЬЮ: Черновики категории '$category'"
  
  if [ -n "$limit" ] && [ "$limit" -gt 0 ]; then
    echo " Будут показаны первые $limit постов:"
    docker exec $WP_CONTAINER wp --allow-root post list \
      --post_type=post \
      --post_status="$status" \
      --category_name="$category" \
      --orderby=date \
      --order=asc \
      --posts_per_page="$limit" \
      --fields=ID,post_title,post_date \
      --format=table
  else
    echo " Все черновики категории:"
    docker exec $WP_CONTAINER wp --allow-root post list \
      --post_type=post \
      --post_status="$status" \
      --category_name="$category" \
      --orderby=date \
      --order=asc \
      --fields=ID,post_title,post_date \
      --format=table
  fi
  
  total_count=$(docker exec $WP_CONTAINER wp --allow-root post list \
    --post_type=post \
    --post_status="$status" \
    --category_name="$category" \
    --format=count)
  
  echo ""
  echo " Всего черновиков в категории: $total_count"
}

case $ACTION in
  "publish")
    if [ -n "$POST_COUNT" ] && [ "$POST_COUNT" -eq 0 ]; then
      echo " Количество постов должно быть больше 0"
      exit 1
    fi
    
    if [ -n "$POST_COUNT" ]; then
      echo " Публикую $POST_COUNT черновиков категории: $CATEGORY_NAME"
    else
      echo " Публикую ВСЕ черновики категории: $CATEGORY_NAME"
    fi
    
    POST_IDS=$(get_posts "draft" "$CATEGORY_NAME" "$POST_COUNT")
    
    if [ -z "$POST_IDS" ]; then
      echo "  В категории '$CATEGORY_NAME' нет черновиков"
      exit 0
    fi
    
    count=0
    total_to_publish=$(echo "$POST_IDS" | wc -w)
    echo " Будет опубликовано: $total_to_publish постов"
    
    for post_id in $POST_IDS; do
      post_title=$(docker exec $WP_CONTAINER wp --allow-root post get $post_id --field=post_title)
      post_date=$(docker exec $WP_CONTAINER wp --allow-root post get $post_id --field=post_date)
      
      echo " Публикую: '$post_title' (ID: $post_id, Дата: $post_date)"
      
      if docker exec $WP_CONTAINER wp --allow-root post update $post_id --post_status=publish; then
        echo " Опубликован: $post_title"
        ((count++))
      else
        echo " Ошибка публикации: $post_title"
      fi
    done
    
    echo ""
    echo " Опубликовано $count из $total_to_publish постов категории '$CATEGORY_NAME'"
    
    # Показываем сколько осталось черновиков
    remaining=$(docker exec $WP_CONTAINER wp --allow-root post list \
      --post_type=post \
      --post_status=draft \
      --category_name="$CATEGORY_NAME" \
      --format=count)
    echo " Осталось черновиков: $remaining"
    ;;

  "hide")
    if [ -n "$POST_COUNT" ] && [ "$POST_COUNT" -eq 0 ]; then
      echo " Количество постов должно быть больше 0"
      exit 1
    fi
    
    if [ -n "$POST_COUNT" ]; then
      echo " Скрываю $POST_COUNT постов категории: $CATEGORY_NAME"
    else
      echo " Скрываю ВСЕ посты категории: $CATEGORY_NAME"
    fi
    
    POST_IDS=$(get_posts "publish" "$CATEGORY_NAME" "$POST_COUNT")
    
    if [ -z "$POST_IDS" ]; then
      echo "  В категории '$CATEGORY_NAME' нет опубликованных постов"
      exit 0
    fi
    
    count=0
    total_to_hide=$(echo "$POST_IDS" | wc -w)
    
    for post_id in $POST_IDS; do
      post_title=$(docker exec $WP_CONTAINER wp --allow-root post get $post_id --field=post_title)
      echo " Скрываю: '$post_title'"
      
      docker exec $WP_CONTAINER wp --allow-root post update $post_id --post_status=draft
      ((count++))
    done
    
    echo " Скрыто $count из $total_to_hide постов"
    ;;

  "schedule")
    if [ -n "$POST_COUNT" ] && [ "$POST_COUNT" -eq 0 ]; then
      echo " Количество постов должно быть больше 0"
      exit 1
    fi
    
    TOMORROW=$(date -d "tomorrow" "+%Y-%m-%d 09:00:00")
    
    if [ -n "$POST_COUNT" ]; then
      echo " Планирую $POST_COUNT постов категории: $CATEGORY_NAME на $TOMORROW"
    else
      echo " Планирую ВСЕ посты категории: $CATEGORY_NAME на $TOMORROW"
    fi
    
    POST_IDS=$(get_posts "draft" "$CATEGORY_NAME" "$POST_COUNT")
    
    if [ -z "$POST_IDS" ]; then
      echo "  В категории '$CATEGORY_NAME' нет черновиков"
      exit 0
    fi
    
    count=0
    total_to_schedule=$(echo "$POST_IDS" | wc -w)
    
    for post_id in $POST_IDS; do
      post_title=$(docker exec $WP_CONTAINER wp --allow-root post get $post_id --field=post_title)
      echo " Планирую: '$post_title' на $TOMORROW"
      
      docker exec $WP_CONTAINER wp --allow-root post update $post_id \
        --post_status=future \
        --post_date="$TOMORROW"
      ((count++))
    done
    
    echo " Запланировано $count из $total_to_schedule постов"
    ;;

  "preview")
    show_preview "$CATEGORY_NAME" "$POST_COUNT"
    ;;

  "list")
    echo " Посты категории: $CATEGORY_NAME"
    
    if [ -n "$POST_COUNT" ] && [ "$POST_COUNT" -gt 0 ]; then
      docker exec $WP_CONTAINER wp --allow-root post list \
        --post_type=post \
        --category_name="$CATEGORY_NAME" \
        --posts_per_page="$POST_COUNT" \
        --fields=ID,post_title,post_status,post_date \
        --format=table
    else
      docker exec $WP_CONTAINER wp --allow-root post list \
        --post_type=post \
        --category_name="$CATEGORY_NAME" \
        --fields=ID,post_title,post_status,post_date \
        --format=table
    fi
    ;;

  "count")
    echo " Статистика категории: $CATEGORY_NAME"
    
    echo ""
    echo "Опубликовано:"
    docker exec $WP_CONTAINER wp --allow-root post list \
      --post_type=post \
      --post_status=publish \
      --category_name="$CATEGORY_NAME" \
      --format=count
      
    echo "Черновики:"
    docker exec $WP_CONTAINER wp --allow-root post list \
      --post_type=post \
      --post_status=draft \
      --category_name="$CATEGORY_NAME" \
      --format=count
      
    echo "Запланировано:"
    docker exec $WP_CONTAINER wp --allow-root post list \
      --post_type=post \
      --post_status=future \
      --category_name="$CATEGORY_NAME" \
      --format=count
    
    echo "Всего:"
    docker exec $WP_CONTAINER wp --allow-root post list \
      --post_type=post \
      --category_name="$CATEGORY_NAME" \
      --format=count
    ;;
    
  *)
    show_usage
    exit 1
    ;;
esac
