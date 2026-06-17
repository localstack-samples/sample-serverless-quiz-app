#!/bin/bash

API_NAME="QuizAPI"
AWS_ENDPOINT_URL=${AWS_ENDPOINT_URL:-"http://localhost:4566"}

GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" >&2
}

error_log() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" >&2
}

API_ID=$(awslocal apigateway get-rest-apis \
  --query "items[?name=='$API_NAME'].id" \
  --output text)

if [ -z "$API_ID" ]; then
    error_log "API ID not found."
    exit 1
fi

API_ENDPOINT="$AWS_ENDPOINT_URL/_aws/execute-api/$API_ID/prod"

log "Waiting for API Lambda functions to become active..."
for FUNCTION_NAME in CreateQuizFunction SubmitQuizFunction; do
    awslocal lambda wait function-active-v2 --function-name ${FUNCTION_NAME}
done

create_quiz() {
    local quiz_data=$1
    local response=$(curl -s -X POST "$API_ENDPOINT/createquiz" \
        -H "Content-Type: application/json" \
        -d "$quiz_data")

    if [ "$(echo $response | jq -r 'has("QuizID")')" = "true" ]; then
        local quiz_id=$(echo $response | jq -r '.QuizID')
        log "Created quiz with ID: $quiz_id"
        echo $quiz_id
    else
        error_log "Failed to create quiz: $response"
        return 1
    fi
}

submit_quiz_response() {
    local username=$1
    local quiz_id=$2

    local compact_answers=$(echo "$answers" | jq -c '.')

    local payload=$(jq -n \
        --arg Username "$username" \
        --arg QuizID "$quiz_id" \
        --argjson Answers "$compact_answers" \
        '{Username: $Username, QuizID: $QuizID, Answers: $Answers}')

    local response
    local http_code
    response=$(curl -s -w "%{http_code}" -o /tmp/response_body.txt -X POST "$API_ENDPOINT/submitquiz" \
        -H "Content-Type: application/json" \
        -d "$payload")
    http_code=$response
    response_body=$(cat /tmp/response_body.txt)
    rm /tmp/response_body.txt

    if [[ $http_code -ne 200 ]]; then
        error_log "Failed to submit response for $username: HTTP $http_code - $response_body"
    else
        log "Successfully submitted quiz response for user: $username"
    fi
}

# Create Comic Book Quiz
log "Creating Comic Book Quiz..."
COMIC_QUIZ_DATA=$(cat <<EOF
{
    "Title": "Comic Book Quiz",
    "Visibility": "Public",
    "EnableTimer": true,
    "TimerSeconds": 10,
    "Questions": [
        {
            "QuestionText": "Who was the first Marvel superhero to get their own comic book?",
            "Options": ["A. Iron Man", "B. Captain America", "C. Spider-Man", "D. Thor"],
            "CorrectAnswer": "B. Captain America",
            "Trivia": "This hero, known for battling villains like Red Skull, first appeared during World War II as a symbol of American patriotism."
        },
        {
            "QuestionText": "Which DC superhero is also known as \"The Dark Knight\"?",
            "Options": ["A. Superman", "B. The Flash", "C. Batman", "D. Green Lantern"],
            "CorrectAnswer": "C. Batman",
            "Trivia": "This hero, whose parents were tragically murdered, relies on gadgets and detective skills rather than superpowers to fight crime."
        },
        {
            "QuestionText": "In the Marvel Universe, what is Wolverine's skeleton coated with?",
            "Options": ["A. Vibranium", "B. Adamantium", "C. Titanium", "D. Kryptonite"],
            "CorrectAnswer": "B. Adamantium",
            "Trivia": "This indestructible metal is also used in the shield of a famous fellow superhero and makes Wolverine nearly unbreakable."
        },
        {
            "QuestionText": "Who is Wonder Woman's primary antagonist in Greek mythology?",
            "Options": ["A. Zeus", "B. Hades", "C. Ares", "D. Hermes"],
            "CorrectAnswer": "C. Ares",
            "Trivia": "Known as the god of war, this deity frequently clashes with Wonder Woman, challenging her ideals of peace and justice."
        },
        {
            "QuestionText": "Which character from Marvel and DC is known for wielding a magical hammer that only \"the worthy\" can lift?",
            "Options": ["A. Wonder Woman", "B. Thor", "C. Superman", "D. Doctor Strange"],
            "CorrectAnswer": "B. Thor",
            "Trivia": "This weapon, named Mjolnir, is tied to ancient Norse mythology and grants its wielder incredible power."
        }
    ]
}
EOF
)
COMIC_BOOK_QUIZ_ID=$(create_quiz "$COMIC_QUIZ_DATA")

# Submit Comic Book Quiz responses
log "Submitting responses for Comic Book Quiz..."

answers=$(cat <<EOF
{
    "0": {"Answer": "A. Iron Man", "TimeTaken": 9},
    "1": {"Answer": "C. Batman", "TimeTaken": 7},
    "2": {"Answer": "A. Vibranium", "TimeTaken": 10},
    "3": {"Answer": "B. Hades", "TimeTaken": 6},
    "4": {"Answer": "B. Thor", "TimeTaken": 8}
}
EOF
)
submit_quiz_response "heroFan42" "$COMIC_BOOK_QUIZ_ID"

answers=$(cat <<EOF
{
    "0": {"Answer": "B. Captain America", "TimeTaken": 4},
    "1": {"Answer": "D. Green Lantern", "TimeTaken": 9},
    "2": {"Answer": "C. Titanium", "TimeTaken": 10},
    "3": {"Answer": "C. Ares", "TimeTaken": 5},
    "4": {"Answer": "C. Superman", "TimeTaken": 7}
}
EOF
)
submit_quiz_response "dcMarvelLover" "$COMIC_BOOK_QUIZ_ID"

answers=$(cat <<EOF
{
    "0": {"Answer": "B. Captain America", "TimeTaken": 5},
    "1": {"Answer": "A. Superman", "TimeTaken": 9},
    "2": {"Answer": "B. Adamantium", "TimeTaken": 6},
    "3": {"Answer": "A. Zeus", "TimeTaken": 8},
    "4": {"Answer": "B. Thor", "TimeTaken": 10}
}
EOF
)
submit_quiz_response "quizMaster19" "$COMIC_BOOK_QUIZ_ID"

# Create AWS Quiz
log "Creating AWS Quiz..."
AWS_QUIZ_DATA=$(cat <<EOF
{
    "Title": "AWS Quiz",
    "Visibility": "Public",
    "EnableTimer": true,
    "TimerSeconds": 15,
    "Questions": [
        {
            "QuestionText": "Which AWS service is primarily used for hosting applications and websites?",
            "Options": ["A. Amazon RDS", "B. Amazon EC2", "C. Amazon S3", "D. AWS Lambda"],
            "CorrectAnswer": "B. Amazon EC2",
            "Trivia": "This service can automatically scale your application based on demand and is commonly used with other compute resources."
        },
        {
            "QuestionText": "What does the S3 in Amazon S3 stand for?",
            "Options": ["A. Simple Storage Service", "B. Secure Storage Solution", "C. Scalable Storage System", "D. Synchronized Storage Service"],
            "CorrectAnswer": "A. Simple Storage Service",
            "Trivia": "This storage service has three components in its name, hinting at its redundancy and durability."
        },
        {
            "QuestionText": "Which AWS database service is a fully-managed relational database?",
            "Options": ["A. Amazon DynamoDB", "B. Amazon Aurora", "C. Amazon RDS", "D. Amazon Redshift"],
            "CorrectAnswer": "C. Amazon RDS",
            "Trivia": "It supports popular engines like MySQL and PostgreSQL and is designed to handle tasks like backups and recovery automatically."
        },
        {
            "QuestionText": "What AWS service is known for running code in response to events without requiring server management?",
            "Options": ["A. AWS Step Functions", "B. AWS Lambda", "C. AWS Fargate", "D. AWS Batch"],
            "CorrectAnswer": "B. AWS Lambda",
            "Trivia": "This service charges based on execution time and is often used in event-driven architectures."
        },
        {
            "QuestionText": "In AWS, what is IAM used for?",
            "Options": ["A. Infrastructure and Monitoring", "B. Identity and Access Management", "C. Intelligent Application Monitoring", "D. Instance Access Management"],
            "CorrectAnswer": "B. Identity and Access Management",
            "Trivia": "This service helps manage access and permissions, ensuring that users and services have the correct level of access."
        }
    ]
}
EOF
)
AWS_QUIZ_ID=$(create_quiz "$AWS_QUIZ_DATA")

# Submit AWS Quiz responses
log "Submitting responses for AWS Quiz..."

answers=$(cat <<EOF
{
    "0": {"Answer": "B. Amazon EC2", "TimeTaken": 4},
    "1": {"Answer": "C. Scalable Storage System", "TimeTaken": 7},
    "2": {"Answer": "A. Amazon DynamoDB", "TimeTaken": 10},
    "3": {"Answer": "B. AWS Lambda", "TimeTaken": 5},
    "4": {"Answer": "B. Identity and Access Management", "TimeTaken": 9}
}
EOF
)
submit_quiz_response "awsExplorer" "$AWS_QUIZ_ID"

answers=$(cat <<EOF
{
    "0": {"Answer": "A. Amazon RDS", "TimeTaken": 8},
    "1": {"Answer": "A. Simple Storage Service", "TimeTaken": 6},
    "2": {"Answer": "C. Amazon RDS", "TimeTaken": 9},
    "3": {"Answer": "B. AWS Lambda", "TimeTaken": 7},
    "4": {"Answer": "D. Instance Access Management", "TimeTaken": 10}
}
EOF
)
submit_quiz_response "cloudRookie" "$AWS_QUIZ_ID"

answers=$(cat <<EOF
{
    "0": {"Answer": "B. Amazon EC2", "TimeTaken": 6},
    "1": {"Answer": "A. Simple Storage Service", "TimeTaken": 8},
    "2": {"Answer": "C. Amazon RDS", "TimeTaken": 9},
    "3": {"Answer": "A. AWS Step Functions", "TimeTaken": 10},
    "4": {"Answer": "B. Identity and Access Management", "TimeTaken": 7}
}
EOF
)
submit_quiz_response "devOpsNinja" "$AWS_QUIZ_ID"

# Create Star Wars Quiz
log "Creating Star Wars Quiz..."
STAR_WARS_QUIZ_DATA=$(cat <<EOF
{
    "Title": "Star Wars Quiz",
    "Visibility": "Public",
    "EnableTimer": true,
    "TimerSeconds": 10,
    "Questions": [
        {
            "QuestionText": "What is the name of Han Solo's ship?",
            "Options": ["A. Star Destroyer", "B. Millennium Falcon", "C. X-Wing", "D. TIE Fighter"],
            "CorrectAnswer": "B. Millennium Falcon",
            "Trivia": "This ship completed the Kessel Run in less than twelve parsecs and has become one of the most iconic vessels in the galaxy."
        },
        {
            "QuestionText": "Who trained Luke Skywalker in the ways of the Force?",
            "Options": ["A. Obi-Wan Kenobi", "B. Yoda", "C. Qui-Gon Jinn", "D. Mace Windu"],
            "CorrectAnswer": "B. Yoda",
            "Trivia": "This wise mentor, hidden away on Dagobah, was small in stature but strong with the Force."
        },
        {
            "QuestionText": "What color is Mace Windu's lightsaber?",
            "Options": ["A. Blue", "B. Green", "C. Purple", "D. Red"],
            "CorrectAnswer": "C. Purple",
            "Trivia": "This lightsaber color is unique in the Star Wars films, setting Mace Windu apart from other Jedi."
        },
        {
            "QuestionText": "What is the home planet of Chewbacca and the Wookiees?",
            "Options": ["A. Tatooine", "B. Hoth", "C. Kashyyyk", "D. Endor"],
            "CorrectAnswer": "C. Kashyyyk",
            "Trivia": "This forested planet was featured in Star Wars: Episode III - Revenge of the Sith."
        },
        {
            "QuestionText": "Who is the father of Princess Leia and Luke Skywalker?",
            "Options": ["A. Yoda", "B. Darth Maul", "C. Darth Vader", "D. Emperor Palpatine"],
            "CorrectAnswer": "C. Darth Vader",
            "Trivia": "Once a Jedi Knight named Anakin, he is also known by a darker name after his fall to the dark side."
        }
    ]
}
EOF
)
STAR_WARS_QUIZ_ID=$(create_quiz "$STAR_WARS_QUIZ_DATA")

# Submit Star Wars Quiz responses
log "Submitting responses for Star Wars Quiz..."

answers=$(cat <<EOF
{
    "0": {"Answer": "B. Millennium Falcon", "TimeTaken": 6},
    "1": {"Answer": "A. Obi-Wan Kenobi", "TimeTaken": 9},
    "2": {"Answer": "C. Purple", "TimeTaken": 5},
    "3": {"Answer": "A. Tatooine", "TimeTaken": 10},
    "4": {"Answer": "C. Darth Vader", "TimeTaken": 7}
}
EOF
)
submit_quiz_response "jediMaster101" "$STAR_WARS_QUIZ_ID"

answers=$(cat <<EOF
{
    "0": {"Answer": "B. Millennium Falcon", "TimeTaken": 5},
    "1": {"Answer": "B. Yoda", "TimeTaken": 4},
    "2": {"Answer": "D. Red", "TimeTaken": 8},
    "3": {"Answer": "C. Kashyyyk", "TimeTaken": 7},
    "4": {"Answer": "A. Yoda", "TimeTaken": 9}
}
EOF
)
submit_quiz_response "starWarsFan88" "$STAR_WARS_QUIZ_ID"

answers=$(cat <<EOF
{
    "0": {"Answer": "C. X-Wing", "TimeTaken": 10},
    "1": {"Answer": "B. Yoda", "TimeTaken": 6},
    "2": {"Answer": "C. Purple", "TimeTaken": 5},
    "3": {"Answer": "D. Endor", "TimeTaken": 8},
    "4": {"Answer": "C. Darth Vader", "TimeTaken": 10}
}
EOF
)
submit_quiz_response "galacticExplorer" "$STAR_WARS_QUIZ_ID"
