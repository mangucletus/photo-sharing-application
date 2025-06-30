import React, { useState } from 'react';
import { Amplify } from 'aws-amplify';
import { Authenticator } from '@aws-amplify/ui-react';
import { uploadData } from 'aws-amplify/storage';
import '@aws-amplify/ui-react/styles.css';

// Configure Amplify
Amplify.configure({
  Auth: {
    Cognito: {
      userPoolId: process.env.REACT_APP_USER_POOL_ID,
      userPoolClientId: process.env.REACT_APP_USER_POOL_CLIENT_ID,
      loginWith: {
        email: true,
      },
      signUpVerificationMethod: 'code',
      userAttributes: {
        email: {
          required: true,
        },
      },
      allowGuestAccess: false,
      passwordFormat: {
        minLength: 8,
        requireLowercase: true,
        requireUppercase: true,
        requireNumbers: true,
        requireSpecialCharacters: false,
      },
    },
  },
  Storage: {
    S3: {
      bucket: process.env.REACT_APP_IMAGES_BUCKET,
      region: process.env.REACT_APP_AWS_REGION,
    },
  },
});

function App() {
  return (
    <Authenticator>
      {({ signOut, user }) => (
        <PhotoSharingApp user={user} signOut={signOut} />
      )}
    </Authenticator>
  );
}

function PhotoSharingApp({ user, signOut }) {
  const [uploading, setUploading] = useState(false);
  const [message, setMessage] = useState('');

  const handleFileUpload = async (event) => {
    const file = event.target.files[0];
    if (!file) return;

    if (!file.type.startsWith('image/')) {
      setMessage('Please select an image file');
      return;
    }

    if (file.size > 10 * 1024 * 1024) {
      setMessage('File size must be less than 10MB');
      return;
    }

    setUploading(true);
    setMessage('Uploading...');
    
    try {
      const fileName = `${Date.now()}-${file.name}`;
      
      await uploadData({
        key: fileName,
        data: file,
        options: {
          contentType: file.type,
          metadata: {
            userId: user.username,
            uploadTime: new Date().toISOString(),
          },
        },
      });

      setMessage('Image uploaded successfully!');
      
    } catch (error) {
      console.error('Upload error:', error);
      setMessage('Upload failed. Please try again.');
    } finally {
      setUploading(false);
      event.target.value = '';
    }
  };

  return (
    <div style={{ padding: '20px', fontFamily: 'Arial, sans-serif' }}>
      <div style={{ marginBottom: '20px', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <h1>Photo Sharing App</h1>
        <div>
          <span>Welcome, {user.username}! </span>
          <button onClick={signOut}>Sign Out</button>
        </div>
      </div>

      <div style={{ marginBottom: '20px' }}>
        <h2>Upload Photo</h2>
        <input
          type="file"
          accept="image/*"
          onChange={handleFileUpload}
          disabled={uploading}
        />
        {message && (
          <div style={{ marginTop: '10px', padding: '10px', backgroundColor: '#f0f0f0' }}>
            {message}
          </div>
        )}
      </div>

      <div>
        <h2>Your Photos</h2>
        <p>Upload an image to see it processed and stored.</p>
      </div>
    </div>
  );
}

export default App;