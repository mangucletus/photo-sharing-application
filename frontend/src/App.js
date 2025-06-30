import React, { useState, useEffect } from 'react';
import { Amplify } from 'aws-amplify';
import { Authenticator } from '@aws-amplify/ui-react';
import { uploadData } from 'aws-amplify/storage';
import '@aws-amplify/ui-react/styles.css';
import './App.css';

// Configure Amplify (these values will be injected during build)
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
  const [images, setImages] = useState([]);
  const [uploading, setUploading] = useState(false);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    loadImages();
  }, []);

  const loadImages = async () => {
    try {
      // In a real app, you'd fetch from DynamoDB or your API
      // For now, we'll just show a placeholder
      setImages([]);
      setLoading(false);
    } catch (error) {
      console.error('Error loading images:', error);
      setLoading(false);
    }
  };

  const handleFileUpload = async (event) => {
    const file = event.target.files[0];
    if (!file) return;

    // Validate file type
    if (!file.type.startsWith('image/')) {
      alert('Please select an image file');
      return;
    }

    // Validate file size (max 10MB)
    if (file.size > 10 * 1024 * 1024) {
      alert('File size must be less than 10MB');
      return;
    }

    setUploading(true);
    
    try {
      const fileName = `${Date.now()}-${file.name}`;
      
      const result = await uploadData({
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

      console.log('Upload successful:', result);
      
      // Refresh images list
      setTimeout(() => {
        loadImages();
      }, 2000); // Wait for Lambda to process

      alert('Image uploaded successfully!');
      
    } catch (error) {
      console.error('Upload error:', error);
      alert('Upload failed. Please try again.');
    } finally {
      setUploading(false);
      event.target.value = ''; // Reset file input
    }
  };

  return (
    <div className="app">
      <header className="app-header">
        <h1>📸 Photo Sharing App</h1>
        <div className="user-info">
          <span>Welcome, {user.username}!</span>
          <button onClick={signOut} className="sign-out-btn">
            Sign Out
          </button>
        </div>
      </header>

      <main className="main-content">
        <section className="upload-section">
          <h2>Upload a Photo</h2>
          <div className="upload-area">
            <input
              type="file"
              accept="image/*"
              onChange={handleFileUpload}
              disabled={uploading}
              className="file-input"
              id="file-upload"
            />
            <label htmlFor="file-upload" className="upload-label">
              {uploading ? (
                <div className="uploading">
                  <div className="spinner"></div>
                  Uploading...
                </div>
              ) : (
                <>
                  <div className="upload-icon">📁</div>
                  <div>Click to select an image</div>
                  <div className="upload-hint">Max size: 10MB</div>
                </>
              )}
            </label>
          </div>
        </section>

        <section className="gallery-section">
          <h2>Your Photos</h2>
          {loading ? (
            <div className="loading">Loading photos...</div>
          ) : images.length === 0 ? (
            <div className="empty-gallery">
              <div className="empty-icon">🖼️</div>
              <p>No photos yet. Upload your first image!</p>
            </div>
          ) : (
            <div className="gallery">
              {images.map((image, index) => (
                <div key={index} className="gallery-item">
                  <img
                    src={image.thumbnailUrl}
                    alt={image.originalKey}
                    className="thumbnail"
                  />
                  <div className="image-info">
                    <p className="image-name">{image.originalKey}</p>
                    <p className="upload-time">
                      {new Date(image.uploadTime).toLocaleDateString()}
                    </p>
                  </div>
                </div>
              ))}
            </div>
          )}
        </section>
      </main>
    </div>
  );
}

export default App;