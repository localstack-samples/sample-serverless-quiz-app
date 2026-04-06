import pytest
import boto3
import requests
import localstack.sdk.aws
import json
import time

API_NAME = 'QuizAPI'
STAGE_NAME = "prod"


@pytest.fixture(scope='module')
def api_endpoint():
    apigateway_client = boto3.client('apigateway', endpoint_url='http://localhost:4566')
    lambda_client = boto3.client('lambda', endpoint_url='http://localhost:4566')

    response = apigateway_client.get_rest_apis()
    api_list = response.get('items', [])
    api = next((item for item in api_list if item['name'] == API_NAME), None)

    if not api:
        raise Exception(f"API {API_NAME} not found.")

    API_ID = api['id']
    API_ENDPOINT = f"http://localhost:4566/_aws/execute-api/{API_ID}/{STAGE_NAME}"

    print(f"API Endpoint: {API_ENDPOINT}")

    time.sleep(2)

    return API_ENDPOINT

def test_quiz_workflow(api_endpoint):
    create_quiz_payload = {
        "Title": "Sample Quiz",
        "Visibility": "Public",
        "EnableTimer": True,
        "TimerSeconds": 10,
        "Questions": [
            {
                "QuestionText": "What is the capital of France?",
                "Options": ["A. Berlin", "B. London", "C. Madrid", "D. Paris"],
                "CorrectAnswer": "D. Paris",
                "Trivia": "Paris is known as the City of Light."
            },
            {
                "QuestionText": "Who wrote Hamlet?",
                "Options": ["A. Dickens", "B. Shakespeare", "C. Twain", "D. Hemingway"],
                "CorrectAnswer": "B. Shakespeare",
                "Trivia": "Shakespeare is often called England's national poet."
            },
            {
                "QuestionText": "What is the largest planet in our solar system?",
                "Options": ["A. Earth", "B. Mars", "C. Jupiter", "D. Saturn"],
                "CorrectAnswer": "C. Jupiter",
                "Trivia": "Jupiter is so large that all the other planets in the solar system could fit inside it."
            },
            {
                "QuestionText": "Which element has the chemical symbol 'O'?",
                "Options": ["A. Gold", "B. Oxygen", "C. Silver", "D. Iron"],
                "CorrectAnswer": "B. Oxygen",
                "Trivia": "Oxygen makes up about 21% of the Earth's atmosphere."
            },
            {
                "QuestionText": "In which year did World War II end?",
                "Options": ["A. 1943", "B. 1945", "C. 1947", "D. 1950"],
                "CorrectAnswer": "B. 1945",
                "Trivia": "The war ended with the surrender of Japan on September 2, 1945."
            }
        ]
    }

    response = requests.post(
        f"{api_endpoint}/createquiz",
        headers={"Content-Type": "application/json"},
        data=json.dumps(create_quiz_payload)
    )

    assert response.status_code == 200
    quiz_creation_response = response.json()
    assert 'QuizID' in quiz_creation_response
    quiz_id = quiz_creation_response['QuizID']

    print(f"Quiz created with ID: {quiz_id}")

    response = requests.get(f"{api_endpoint}/listquizzes")
    assert response.status_code == 200
    quizzes_list = response.json().get('Quizzes', [])
    quiz_titles = [quiz['Title'] for quiz in quizzes_list]
    assert "Sample Quiz" in quiz_titles

    response = requests.get(f"{api_endpoint}/getquiz?quiz_id={quiz_id}")
    assert response.status_code == 200
    quiz_details = response.json()
    assert quiz_details['Title'] == "Sample Quiz"
    assert len(quiz_details['Questions']) == 5

    submissions = []
    users = [
        {
            "Username": "user1",
            "Answers": {
                "0": {"Answer": "D. Paris", "TimeTaken": 8},
                "1": {"Answer": "B. Shakespeare", "TimeTaken": 5},
                "2": {"Answer": "C. Jupiter", "TimeTaken": 6},
                "3": {"Answer": "B. Oxygen", "TimeTaken": 7},
                "4": {"Answer": "B. 1945", "TimeTaken": 9}
            }
        },
        {
            "Username": "user2",
            "Email": "user@example.com",
            "Answers": {
                "0": {"Answer": "D. Paris", "TimeTaken": 7},
                "1": {"Answer": "B. Shakespeare", "TimeTaken": 6},
                "2": {"Answer": "D. Saturn", "TimeTaken": 5},  # Incorrect
                "3": {"Answer": "B. Oxygen", "TimeTaken": 8},
                "4": {"Answer": "B. 1945", "TimeTaken": 10}
            }
        },
        {
            "Username": "user3",
            "Answers": {
                "0": {"Answer": "A. Berlin", "TimeTaken": 9},  # Incorrect
                "1": {"Answer": "D. Hemingway", "TimeTaken": 4},  # Incorrect
                "2": {"Answer": "C. Jupiter", "TimeTaken": 11},  # Exceeds time
                "3": {"Answer": "B. Oxygen", "TimeTaken": 12},  # Exceeds time
                "4": {"Answer": "B. 1945", "TimeTaken": 13}     # Exceeds time
            }
        }
    ]

    for user in users:
        submission_payload = {
            "Username": user["Username"],
            "QuizID": quiz_id,
            "Answers": user["Answers"]
        }
        if "Email" in user:
            submission_payload["Email"] = user["Email"]

        response = requests.post(
            f"{api_endpoint}/submitquiz",
            headers={"Content-Type": "application/json"},
            data=json.dumps(submission_payload)
        )
        assert response.status_code == 200
        submission_response = response.json()
        assert 'SubmissionID' in submission_response
        submissions.append({
            "Username": user["Username"],
            "SubmissionID": submission_response["SubmissionID"]
        })

        print(f"{user['Username']} submitted quiz with SubmissionID: {submission_response['SubmissionID']}")

    time.sleep(5)

    top_n = 3
    expected_leaderboard_size = min(top_n, len(users))
    leaderboard_url = f"{api_endpoint}/getleaderboard?quiz_id={quiz_id}&top={top_n}"
    leaderboard = None

    # Scoring runs asynchronously, so keep polling until all expected top entries are available.
    leaderboard_deadline = time.time() + 30
    while time.time() < leaderboard_deadline:
        response = requests.get(leaderboard_url)
        assert response.status_code == 200
        current_leaderboard = response.json()
        if (
            isinstance(current_leaderboard, list)
            and len(current_leaderboard) == expected_leaderboard_size
        ):
            leaderboard = current_leaderboard
            break
        time.sleep(2)

    assert leaderboard is not None, (
        f"Failed to retrieve {expected_leaderboard_size} leaderboard entries after retries"
    )
    assert len(leaderboard) == expected_leaderboard_size
    expected_scores = {
        "user1": None,
        "user2": None,
        "user3": None
    }

    max_score = 100
    timer_seconds = 10

    correct_answers = ["D. Paris", "B. Shakespeare", "C. Jupiter", "B. Oxygen", "B. 1945"]

    def calculate_user_score(user_answers):
        score = 0
        for idx, correct_answer in enumerate(correct_answers):
            user_answer = user_answers[str(idx)]["Answer"]
            time_taken = user_answers[str(idx)]["TimeTaken"]
            if user_answer == correct_answer and time_taken <= timer_seconds:
                question_score = max_score * (1 - (time_taken / timer_seconds))
                score += max(0, question_score)
            else:
                pass
        return score

    for user in users:
        username = user["Username"]
        expected_scores[username] = calculate_user_score(user["Answers"])

    for entry in leaderboard:
        username = entry["Username"]
        actual_score = entry["Score"]
        expected_score = expected_scores[username]
        assert actual_score == pytest.approx(expected_score, abs=0.01)

        print(f"{username} - Expected Score: {expected_score}, Actual Score: {actual_score}")

    for submission in submissions:
        response = requests.get(f"{api_endpoint}/getsubmission?submission_id={submission['SubmissionID']}")
        assert response.status_code == 200
        submission_data = response.json()
        assert submission_data['Username'] == submission['Username']
        assert submission_data['QuizID'] == quiz_id
        assert 'Score' in submission_data
        assert 'UserAnswers' in submission_data

        expected_score = expected_scores[submission['Username']]
        actual_score = submission_data['Score']
        assert actual_score == pytest.approx(expected_score, abs=0.01)

        print(f"Verified submission for {submission['Username']} with Score: {actual_score}")

    client = localstack.sdk.aws.AWSClient()
    sender_email = "sender@example.com"
    messages = client.get_ses_messages(email_filter=sender_email)

    email_found = False
    for message in messages:
        if message.source == sender_email:
            email_found = True
            assert hasattr(message, 'id')
            assert hasattr(message, 'region')
            assert hasattr(message, 'timestamp')
            assert hasattr(message, 'destination')
            assert hasattr(message, 'subject')
            assert hasattr(message, 'body')

            body = message.body
            assert hasattr(body, 'html_part')
            html_content = body.html_part

            print(f"Email content: {html_content}")

    assert email_found, f"No email found sent from {sender_email}"
