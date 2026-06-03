import React, { useEffect, useState } from 'react';
import { useLocation, useNavigate } from 'react-router-dom';
import {
  Container,
  Typography,
  List,
  ListItem,
  ListItemText,
  Button,
  Box,
  CircularProgress,
  Alert,
  Paper,
  Stack,
} from '@mui/material';
import QuizLayout from './QuizLayout';
import StarSharp from '../../src/StarSharp.svg';

function LeaderboardPage() {
  const { state } = useLocation();
  const navigate = useNavigate();
  const { quizID } = state || {};
  const [leaderboardData, setLeaderboardData] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  useEffect(() => {
    if (!quizID) {
      navigate('/');
      return;
    }

    fetch(
      `${process.env.REACT_APP_API_ENDPOINT}/getleaderboard?quiz_id=${quizID}&top=5`
    )
      .then((res) => res.json())
      .then((data) => {
        setLeaderboardData(data);
        setLoading(false);
      })
      .catch((err) => {
        console.error('Error fetching leaderboard data:', err);
        setError('Failed to fetch leaderboard data. Please try again later.');
        setLoading(false);
      });
  }, [quizID, navigate]);

  const handleGoHome = () => {
    navigate('/');
  };

  const handleViewEmailDemo = () => {
    let targetURL = '';
    const hostname = window.location.hostname;

    if (hostname.includes('localhost')) {
      targetURL = `http://localhost.localstack.cloud:4566/_extension/mailhog/`;
    } else {
      const baseOrigin = window.location.origin;
      targetURL = `${baseOrigin}/_extension/mailhog/`;
    }

    window.open(targetURL, '_blank');
  };

  if (loading) {
    return (
      <Container maxWidth="sm" sx={{ textAlign: 'center', marginTop: 8 }}>
        <CircularProgress />
        <Typography variant="h6" sx={{ marginTop: 2 }}>
          Loading leaderboard...
        </Typography>
      </Container>
    );
  }

  if (error) {
    return (
      <Container maxWidth="sm" sx={{ textAlign: 'center', marginTop: 8 }}>
        <Alert severity="error" sx={{ marginBottom: 2 }}>
          {error}
        </Alert>
        <Button variant="contained" color="primary" onClick={handleGoHome}>
          Go to Home
        </Button>
      </Container>
    );
  }

  return (
    <QuizLayout>
      <Container maxWidth="sm" className="main-quiz-container">
        <Box sx={{ textAlign: 'center', marginTop: 4, width: '100%' }}>
          <Typography variant="h4" gutterBottom>
            LEADERBOARD
          </Typography>
          <div className="top-scores">
            <div className="podium second-place">
              <Typography
                variant="h5"
                gutterBottom
                sx={{
                  marginTop: '80px',
                  marginLeft: 'auto',
                  marginRight: 'auto',
                }}
              >
                {leaderboardData[1]?.Username}
              </Typography>
              <div className="score">
                <img
                  src={StarSharp}
                  alt="Score"
                  style={{ float: 'left', marginLeft: '10px' }}
                />
                {leaderboardData[1]?.Score}
              </div>
            </div>
            <div className="podium first-place">
              <Typography
                variant="h5"
                gutterBottom
                sx={{
                  marginTop: '80px',
                  marginLeft: 'auto',
                  marginRight: 'auto',
                }}
              >
                {leaderboardData[0]?.Username}
              </Typography>
              <div className="score">
                <img
                  src={StarSharp}
                  alt="Score"
                  style={{ float: 'left', marginLeft: '10px' }}
                />
                {leaderboardData[0]?.Score}
              </div>
            </div>
            <div className="podium third-place">
              <Typography
                variant="h5"
                gutterBottom
                sx={{
                  marginTop: '80px',
                  marginLeft: 'auto',
                  marginRight: 'auto',
                }}
              >
                {leaderboardData[2]?.Username}
              </Typography>
              <div className="score">
                <img
                  src={StarSharp}
                  alt="Score"
                  style={{ float: 'left', marginLeft: '10px' }}
                />
                {leaderboardData[2]?.Score}
              </div>
            </div>
          </div>
          {leaderboardData.length > 0 ? (
            <List component={Paper} sx={{ margin: '0 auto', maxWidth: 600 }}>
              {leaderboardData.map((entry, index) => (
                <ListItem key={index}>
                  <ListItemText
                    primary={`${index + 1}. ${entry.Username}`}
                    secondary={`Score: ${entry.Score}`}
                  />
                </ListItem>
              ))}
            </List>
          ) : (
            <Typography>
              No entries yet. Be the first to take the quiz!
            </Typography>
          )}

          <Box sx={{ marginTop: 4 }}>
            <Stack spacing={2} direction="row" justifyContent="center">
              <Button
                variant="contained"
                color="primary"
                onClick={handleGoHome}
              >
                Go to Home
              </Button>
              <Button
                variant="contained"
                color="secondary"
                onClick={handleViewEmailDemo}
              >
                View Email (Demo)
              </Button>
            </Stack>
          </Box>
        </Box>
      </Container>
    </QuizLayout>
  );
}

export default LeaderboardPage;
