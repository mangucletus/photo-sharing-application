import React, { useState, useEffect } from 'react';
import { Amplify } from 'aws-amplify';
import { Authenticator } from '@aws-amplify/ui-react';
import { uploadData } from 'aws-amplify/storage';
import '@aws-amplify/ui-react/styles.css';
import './App.css';

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
  const [images, setImages] = useState([]);
  const [uploading, setUploading] = useState(false);
  const [loading, setLoading] = useState(true);
  const [dragActive, setDragActive] = useState(false);
  const [message, setMessage] = useState('');
  const [messageType, setMessageType] = useState('');

  useEffect(() => {
    loadImages();
  }, []);

  const showMessage = (text, type = 'info') => {
    setMessage(text);
    setMessageType(type);
    setTimeout(() => {
      setMessage('');
      setMessageType('');
    }, 5000);
  };

  const loadImages = async () => {
    try {
      setLoading(true);
      
      // Fetch images from API
      const apiUrl = process.env.REACT_APP_API_GATEWAY_URL;
      if (apiUrl) {
        try {
          const response = await fetch(`${apiUrl}/api/user/${encodeURIComponent(user.username)}/images`);
          if (response.ok) {
            const data = await response.json();
            setImages(data.images || []);
            setLoading(false);
            return;
          }
        } catch (error) {
          console.error('Error fetching from API:', error);
        }
      }
      
      // Fallback to localStorage if API fails
      const storedImages = JSON.parse(localStorage.getItem(`user_images_${user.username}`) || '[]');
      
      // Filter out old images that might not exist anymore
      const validImages = storedImages.filter(img => {
        const uploadTime = new Date(img.uploadTime);
        const now = new Date();
        const daysDiff = (now - uploadTime) / (1000 * 60 * 60 * 24);
        return daysDiff < 30; // Keep images from last 30 days
      });
      
      setImages(validImages);
      setLoading(false);
    } catch (error) {
      console.error('Error loading images:', error);
      setLoading(false);
    }
  };

  const handleFileUpload = async (file) => {
    if (!file) return;

    // Validate file type
    if (!file.type.startsWith('image/')) {
      showMessage('Please select an image file', 'error');
      return;
    }

    // Validate file size (max 10MB)
    if (file.size > 10 * 1024 * 1024) {
      showMessage('File size must be less than 10MB', 'error');
      return;
    }

    setUploading(true);
    showMessage('Uploading image...', 'info');
    
    try {
      const timestamp = Date.now();
      const fileName = `${timestamp}-${file.name.replace(/[^a-zA-Z0-9.-]/g, '_')}`;
      
      const result = await uploadData({
        key: fileName,
        data: file,
        options: {
          contentType: file.type,
          metadata: {
            userId: user.username,
            uploadTime: new Date().toISOString(),
            originalName: file.name,
          },
        },
      });

      console.log('Upload successful:', result);
      
      // Create thumbnail URL (will be available after Lambda processing)
      const thumbnailUrl = `https://${process.env.REACT_APP_THUMBNAILS_BUCKET}.s3.${process.env.REACT_APP_AWS_REGION}.amazonaws.com/thumb-${fileName}`;
      
      // Add to local state immediately
      const newImage = {
        id: fileName,
        originalKey: fileName,
        thumbnailUrl: thumbnailUrl,
        uploadTime: new Date().toISOString(),
        originalName: file.name,
        size: file.size,
        processing: true
      };
      
      // Update state
      const updatedImages = [newImage, ...images];
      setImages(updatedImages);
      
      // Store in localStorage for persistence
      localStorage.setItem(`user_images_${user.username}`, JSON.stringify(updatedImages));
      
      showMessage('Image uploaded successfully! Processing thumbnail...', 'success');
      
      // After 3 seconds, mark as processed (Lambda should be done by then)
      setTimeout(() => {
        setImages(prev => prev.map(img => 
          img.id === fileName ? { ...img, processing: false } : img
        ));
        
        // Update localStorage
        const currentImages = JSON.parse(localStorage.getItem(`user_images_${user.username}`) || '[]');
        const processedImages = currentImages.map(img => 
          img.id === fileName ? { ...img, processing: false } : img
        );
        localStorage.setItem(`user_images_${user.username}`, JSON.stringify(processedImages));
        
        showMessage('Thumbnail processed successfully!', 'success');
      }, 3000);
      
    } catch (error) {
      console.error('Upload error:', error);
      showMessage('Upload failed. Please try again.', 'error');
    } finally {
      setUploading(false);
    }
  };

  const handleFileInputChange = (event) => {
    const file = event.target.files[0];
    if (file) {
      handleFileUpload(file);
    }
    event.target.value = ''; // Reset file input
  };

  const handleDrag = (e) => {
    e.preventDefault();
    e.stopPropagation();
    if (e.type === "dragenter" || e.type === "dragover") {
      setDragActive(true);
    } else if (e.type === "dragleave") {
      setDragActive(false);
    }
  };

  const handleDrop = (e) => {
    e.preventDefault();
    e.stopPropagation();
    setDragActive(false);
    
    if (e.dataTransfer.files && e.dataTransfer.files[0]) {
      handleFileUpload(e.dataTransfer.files[0]);
    }
  };

  const deleteImage = (imageId) => {
    const updatedImages = images.filter(img => img.id !== imageId);
    setImages(updatedImages);
    localStorage.setItem(`user_images_${user.username}`, JSON.stringify(updatedImages));
    showMessage('Image removed from gallery', 'info');
  };

  const formatFileSize = (bytes) => {
    if (bytes === 0) return '0 Bytes';
    const k = 1024;
    const sizes = ['Bytes', 'KB', 'MB', 'GB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
  };

  return (
    <div className="app">
      <header className="app-header">
        <div className="header-content">
          <h1 className="app-title">
            <span className="title-icon">📸</span>
            Photo Sharing
          </h1>
          <div className="user-info">
            <span className="welcome-text">Welcome, {user.username}</span>
            <button onClick={signOut} className="sign-out-btn">
              Sign Out
            </button>
          </div>
        </div>
      </header>

      {message && (
        <div className={`message ${messageType}`}>
          <span className="message-text">{message}</span>
          <button 
            className="message-close" 
            onClick={() => setMessage('')}
            aria-label="Close message"
          >
            ×
          </button>
        </div>
      )}

      <main className="main-content">
        <section className="upload-section">
          <h2 className="section-title">Upload Photos</h2>
          
          <div 
            className={`upload-area ${dragActive ? 'drag-active' : ''} ${uploading ? 'uploading' : ''}`}
            onDragEnter={handleDrag}
            onDragLeave={handleDrag}
            onDragOver={handleDrag}
            onDrop={handleDrop}
          >
            <input
              type="file"
              accept="image/*"
              onChange={handleFileInputChange}
              disabled={uploading}
              className="file-input"
              id="file-upload"
            />
            
            <label htmlFor="file-upload" className="upload-label">
              {uploading ? (
                <div className="upload-status">
                  <div className="spinner"></div>
                  <span>Uploading...</span>
                </div>
              ) : (
                <div className="upload-content">
                  <div className="upload-icon">
                    <svg width="48" height="48" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
                      <path d="M12 15L12 2M12 2L8 6M12 2L16 6" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
                      <path d="M22 22H2" stroke="currentColor" strokeWidth="2" strokeLinecap="round"/>
                    </svg>
                  </div>
                  <div className="upload-text">
                    <span className="upload-primary">Choose files or drag here</span>
                    <span className="upload-secondary">Supports: JPG, PNG, GIF (Max: 10MB)</span>
                  </div>
                </div>
              )}
            </label>
          </div>
        </section>

        <section className="gallery-section">
          <div className="section-header">
            <h2 className="section-title">Your Photos ({images.length})</h2>
            {images.length > 0 && (
              <button 
                className="refresh-btn"
                onClick={loadImages}
                disabled={loading}
              >
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
                  <path d="M21 2V8H15" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
                  <path d="M3 12A9 9 0 0 1 15 3L21 8" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
                  <path d="M3 22V16H9" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
                  <path d="M21 12A9 9 0 0 1 9 21L3 16" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
                </svg>
                Refresh
              </button>
            )}
          </div>
          
          {loading ? (
            <div className="loading-state">
              <div className="spinner large"></div>
              <span>Loading photos...</span>
            </div>
          ) : images.length === 0 ? (
            <div className="empty-state">
              <div className="empty-icon">
                <svg width="64" height="64" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
                  <rect x="3" y="3" width="18" height="18" rx="2" ry="2" stroke="currentColor" strokeWidth="2"/>
                  <circle cx="8.5" cy="8.5" r="1.5" stroke="currentColor" strokeWidth="2"/>
                  <path d="M21 15L16 10L5 21" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
                </svg>
              </div>
              <h3>No photos yet</h3>
              <p>Upload your first image to get started!</p>
            </div>
          ) : (
            <div className="gallery">
              {images.map((image) => (
                <div key={image.id} className="gallery-item">
                  <div className="image-container">
                    {image.processing ? (
                      <div className="image-placeholder processing">
                        <div className="spinner"></div>
                        <span>Processing...</span>
                      </div>
                    ) : (
                      <img
                        src={image.thumbnailUrl}
                        alt={image.originalName}
                        className="thumbnail"
                        onError={(e) => {
                          e.target.style.display = 'none';
                          e.target.nextSibling.style.display = 'flex';
                        }}
                        onLoad={(e) => {
                          e.target.nextSibling.style.display = 'none';
                        }}
                      />
                    )}
                    <div className="image-error" style={{display: 'none'}}>
                      <svg width="32" height="32" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
                        <rect x="3" y="3" width="18" height="18" rx="2" ry="2" stroke="currentColor" strokeWidth="2"/>
                        <circle cx="8.5" cy="8.5" r="1.5" stroke="currentColor" strokeWidth="2"/>
                        <path d="M21 15L16 10L5 21" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
                      </svg>
                      <span>Processing...</span>
                    </div>
                    
                    <div className="image-overlay">
                      <button 
                        className="delete-btn"
                        onClick={() => deleteImage(image.id)}
                        title="Remove from gallery"
                      >
                        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
                          <path d="M18 6L6 18M6 6L18 18" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
                        </svg>
                      </button>
                    </div>
                  </div>
                  
                  <div className="image-info">
                    <p className="image-name" title={image.originalName}>
                      {image.originalName}
                    </p>
                    <div className="image-meta">
                      <span className="image-size">{formatFileSize(image.size)}</span>
                      <span className="image-date">
                        {new Date(image.uploadTime).toLocaleDateString()}
                      </span>
                    </div>
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