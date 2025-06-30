import React, { useState, useEffect } from 'react';
import { Amplify } from 'aws-amplify';
import { Authenticator } from '@aws-amplify/ui-react';
import { uploadData, remove } from 'aws-amplify/storage';
import { fetchAuthSession } from 'aws-amplify/auth';
import '@aws-amplify/ui-react/styles.css';
import './App.css';

// Configure Amplify
Amplify.configure({
  Auth: {
    Cognito: {
      userPoolId: process.env.REACT_APP_USER_POOL_ID,
      userPoolClientId: process.env.REACT_APP_USER_POOL_CLIENT_ID,
      identityPoolId: process.env.REACT_APP_IDENTITY_POOL_ID,
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

// Image Modal Component
function ImageModal({ image, onClose }) {
  if (!image) return null;

  const handleBackdropClick = (e) => {
    if (e.target === e.currentTarget) {
      onClose();
    }
  };

  const originalImageUrl = `https://${process.env.REACT_APP_IMAGES_BUCKET}.s3.${process.env.REACT_APP_AWS_REGION}.amazonaws.com/${image.originalKey}`;

  return (
    <div className="modal-backdrop" onClick={handleBackdropClick}>
      <div className="modal-content">
        <button className="modal-close" onClick={onClose}>
          <svg width="24" height="24" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
            <path d="M18 6L6 18M6 6l12 12" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
          </svg>
        </button>
        <div className="modal-image-container">
          <img
            src={originalImageUrl}
            alt={image.originalName}
            className="modal-image"
            onError={(e) => {
              console.error('Original image load failed, falling back to thumbnail');
              e.target.src = image.thumbnailUrl;
            }}
          />
        </div>
        <div className="modal-info">
          <h3>{image.originalName}</h3>
          <div className="modal-meta">
            <span>Size: {formatFileSize(image.size)}</span>
            <span>Uploaded: {new Date(image.uploadTime).toLocaleDateString()}</span>
            {image.originalWidth && image.originalHeight && (
              <span>Dimensions: {image.originalWidth} × {image.originalHeight}</span>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}

function PhotoSharingApp({ user, signOut }) {
  const [images, setImages] = useState([]);
  const [uploading, setUploading] = useState(false);
  const [loading, setLoading] = useState(true);
  const [dragActive, setDragActive] = useState(false);
  const [message, setMessage] = useState('');
  const [messageType, setMessageType] = useState('');
  const [uploadProgress, setUploadProgress] = useState(0);
  const [userEmail, setUserEmail] = useState('');
  const [selectedImage, setSelectedImage] = useState(null);
  const [deleting, setDeleting] = useState(new Set());

  useEffect(() => {
    // Get user email from auth session
    const getUserEmail = async () => {
      try {
        const session = await fetchAuthSession();
        const email = session.tokens?.idToken?.payload?.email || user.username;
        setUserEmail(email);
      } catch (error) {
        console.error('Error getting user email:', error);
        setUserEmail(user.username);
      }
    };

    getUserEmail();
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

  const loadImages = async (showLoading = true) => {
    try {
      if (showLoading) setLoading(true);
      
      // Try to fetch from API first
      const apiUrl = process.env.REACT_APP_API_GATEWAY_URL;
      if (apiUrl && user?.username) {
        try {
          console.log('Fetching images from API:', `${apiUrl}/api/user/${encodeURIComponent(user.username)}/images`);
          const response = await fetch(`${apiUrl}/api/user/${encodeURIComponent(user.username)}/images`, {
            method: 'GET',
            headers: {
              'Content-Type': 'application/json',
            },
          });
          
          if (response.ok) {
            const data = await response.json();
            console.log('API Response:', data);
            if (data.images && Array.isArray(data.images)) {
              setImages(data.images);
              if (showLoading) setLoading(false);
              return;
            }
          } else {
            console.warn('API request failed:', response.status, response.statusText);
          }
        } catch (error) {
          console.error('Error fetching from API:', error);
        }
      }
      
      // Fallback to localStorage if API fails or no API URL
      console.log('Using localStorage fallback');
      const storedImages = JSON.parse(localStorage.getItem(`user_images_${user.username}`) || '[]');
      setImages(storedImages);
      if (showLoading) setLoading(false);
    } catch (error) {
      console.error('Error loading images:', error);
      if (showLoading) setLoading(false);
      showMessage('Error loading images', 'error');
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

    // Check if environment variables are set
    if (!process.env.REACT_APP_IMAGES_BUCKET) {
      showMessage('Configuration error: Images bucket not configured', 'error');
      console.error('Missing REACT_APP_IMAGES_BUCKET environment variable');
      return;
    }

    setUploading(true);
    setUploadProgress(0);
    showMessage('Preparing upload...', 'info');
    
    try {
      const timestamp = Date.now();
      const sanitizedFileName = file.name.replace(/[^a-zA-Z0-9.-]/g, '_');
      const fileName = `${timestamp}-${sanitizedFileName}`;
      
      console.log('Starting upload:', {
        fileName,
        fileSize: file.size,
        fileType: file.type,
        bucket: process.env.REACT_APP_IMAGES_BUCKET,
        region: process.env.REACT_APP_AWS_REGION,
        user: user.username
      });

      showMessage('Uploading to S3...', 'info');
      setUploadProgress(25);

      // Upload to S3 using Amplify
      const result = await uploadData({
        key: fileName,
        data: file,
        options: {
          contentType: file.type,
          metadata: {
            'user-id': user.username,
            'upload-time': new Date().toISOString(),
            'original-name': file.name,
          },
          onProgress: ({ transferredBytes, totalBytes }) => {
            if (totalBytes) {
              const progress = Math.round((transferredBytes / totalBytes) * 90) + 10;
              setUploadProgress(progress);
            }
          },
        },
      });

      console.log('Upload result:', result);
      
      setUploadProgress(100);
      showMessage('Image uploaded successfully! Processing thumbnail...', 'success');
      
      // Add image to state immediately for better UX
      const newImage = {
        id: fileName,
        originalKey: fileName,
        thumbnailUrl: `https://${process.env.REACT_APP_THUMBNAILS_BUCKET}.s3.${process.env.REACT_APP_AWS_REGION}.amazonaws.com/thumb-${fileName}`,
        uploadTime: new Date().toISOString(),
        originalName: file.name,
        size: file.size,
        processing: true,
        realUpload: true
      };
      
      setImages(prev => [newImage, ...prev]);
      
      // Store in localStorage as backup
      const updatedImages = [newImage, ...images];
      localStorage.setItem(`user_images_${user.username}`, JSON.stringify(updatedImages));
      
      // Check for thumbnail processing - reduced frequency to avoid constant refreshing
      let attempts = 0;
      const maxAttempts = 6; // Reduced from 10
      const checkThumbnail = async () => {
        attempts++;
        
        try {
          const apiUrl = process.env.REACT_APP_API_GATEWAY_URL;
          if (apiUrl) {
            const response = await fetch(`${apiUrl}/api/user/${encodeURIComponent(user.username)}/images`);
            if (response.ok) {
              const data = await response.json();
              const processedImage = data.images?.find(img => img.originalKey === fileName);
              
              if (processedImage && !processedImage.processing) {
                console.log('Thumbnail processed successfully');
                setImages(prev => prev.map(img => 
                  img.id === fileName ? { ...processedImage, processing: false, realUpload: true } : img
                ));
                showMessage('Thumbnail processed successfully!', 'success');
                return;
              }
            }
          }
        } catch (error) {
          console.log('API check failed, continuing to wait...');
        }
        
        if (attempts < maxAttempts) {
          setTimeout(checkThumbnail, 5000); // Increased interval to 5 seconds
        } else {
          console.warn('Thumbnail processing timed out');
          setImages(prev => prev.map(img => 
            img.id === fileName ? { ...img, processing: false, error: 'Processing timeout' } : img
          ));
          showMessage('Image uploaded but thumbnail processing took longer than expected', 'warning');
          // Final refresh after timeout
          setTimeout(() => loadImages(false), 2000);
        }
      };
      
      // Start checking for thumbnail after 8 seconds (increased delay)
      setTimeout(checkThumbnail, 8000);
      
    } catch (error) {
      console.error('Upload error:', error);
      showMessage(`Upload failed: ${error.message}`, 'error');
    } finally {
      setUploading(false);
      setUploadProgress(0);
    }
  };

  const deleteImage = async (imageId, originalKey) => {
    if (!window.confirm('Are you sure you want to delete this image? This action cannot be undone.')) {
      return;
    }

    setDeleting(prev => new Set([...prev, imageId]));
    
    try {
      // Delete from S3 buckets
      try {
        await remove({ key: originalKey });
        console.log('Deleted original image from S3');
      } catch (s3Error) {
        console.error('Error deleting from S3:', s3Error);
        // Continue with deletion even if S3 fails
      }

      // Delete from API/DynamoDB
      const apiUrl = process.env.REACT_APP_API_GATEWAY_URL;
      if (apiUrl) {
        try {
          const response = await fetch(`${apiUrl}/api/user/${encodeURIComponent(user.username)}/images/${encodeURIComponent(imageId)}`, {
            method: 'DELETE',
            headers: {
              'Content-Type': 'application/json',
            },
          });
          
          if (response.ok) {
            console.log('Deleted image metadata from API');
          } else {
            console.warn('API delete failed:', response.status);
          }
        } catch (apiError) {
          console.error('Error deleting from API:', apiError);
        }
      }

      // Remove from local state
      setImages(prev => prev.filter(img => img.id !== imageId));
      
      // Update localStorage
      const updatedImages = images.filter(img => img.id !== imageId);
      localStorage.setItem(`user_images_${user.username}`, JSON.stringify(updatedImages));
      
      showMessage('Image deleted successfully', 'success');
      
      // Refresh images from API to ensure consistency
      setTimeout(() => loadImages(false), 1000);
      
    } catch (error) {
      console.error('Error deleting image:', error);
      showMessage('Error deleting image. Please try again.', 'error');
    } finally {
      setDeleting(prev => {
        const newDeleting = new Set(prev);
        newDeleting.delete(imageId);
        return newDeleting;
      });
    }
  };

  const handleFileInputChange = (event) => {
    const file = event.target.files[0];
    if (file) {
      handleFileUpload(file);
    }
    event.target.value = '';
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

  const handleImageClick = (image) => {
    setSelectedImage(image);
  };

  const handleCloseModal = () => {
    setSelectedImage(null);
  };

  const formatFileSize = (bytes) => {
    if (bytes === 0) return '0 Bytes';
    const k = 1024;
    const sizes = ['Bytes', 'KB', 'MB', 'GB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
  };

  // Debug info component
  const DebugInfo = () => {
    if (process.env.NODE_ENV !== 'production') {
      return (
        <div style={{ 
          position: 'fixed', 
          bottom: '10px', 
          right: '10px', 
          background: 'rgba(0,0,0,0.8)', 
          color: 'white', 
          padding: '10px', 
          fontSize: '12px',
          borderRadius: '5px',
          zIndex: 1000,
          maxWidth: '300px'
        }}>
          <strong>Debug Info:</strong><br/>
          Images Bucket: {process.env.REACT_APP_IMAGES_BUCKET || 'Not set'}<br/>
          Thumbnails Bucket: {process.env.REACT_APP_THUMBNAILS_BUCKET || 'Not set'}<br/>
          API URL: {process.env.REACT_APP_API_GATEWAY_URL || 'Not set'}<br/>
          User Pool: {process.env.REACT_APP_USER_POOL_ID || 'Not set'}<br/>
          Identity Pool: {process.env.REACT_APP_IDENTITY_POOL_ID || 'Not set'}<br/>
          User: {user?.username}<br/>
          Email: {userEmail}<br/>
          Images Count: {images.length}
        </div>
      );
    }
    return null;
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
            <span className="welcome-text">Welcome, {userEmail}</span>
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
                  <span>Uploading... {uploadProgress}%</span>
                  {uploadProgress > 0 && (
                    <div className="progress-bar">
                      <div 
                        className="progress-fill" 
                        style={{ width: `${uploadProgress}%` }}
                      ></div>
                    </div>
                  )}
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
            <button 
              className="refresh-btn"
              onClick={() => loadImages()}
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
                  <div className="image-container" onClick={() => handleImageClick(image)}>
                    {image.processing ? (
                      <div className="image-placeholder processing">
                        <div className="spinner"></div>
                        <span>Processing thumbnail...</span>
                      </div>
                    ) : image.error ? (
                      <div className="image-placeholder error">
                        <svg width="32" height="32" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
                          <circle cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="2"/>
                          <line x1="15" y1="9" x2="9" y2="15" stroke="currentColor" strokeWidth="2"/>
                          <line x1="9" y1="9" x2="15" y2="15" stroke="currentColor" strokeWidth="2"/>
                        </svg>
                        <span>{image.error}</span>
                      </div>
                    ) : (
                      <>
                        <img
                          src={image.thumbnailUrl}
                          alt={image.originalName}
                          className="thumbnail"
                          onError={(e) => {
                            console.error('Thumbnail load error:', image.thumbnailUrl);
                            e.target.style.display = 'none';
                            e.target.nextSibling.style.display = 'flex';
                          }}
                          onLoad={(e) => {
                            e.target.nextSibling.style.display = 'none';
                          }}
                        />
                        <div className="image-error" style={{display: 'none'}}>
                          <svg width="32" height="32" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
                            <rect x="3" y="3" width="18" height="18" rx="2" ry="2" stroke="currentColor" strokeWidth="2"/>
                            <circle cx="8.5" cy="8.5" r="1.5" stroke="currentColor" strokeWidth="2"/>
                            <path d="M21 15L16 10L5 21" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
                          </svg>
                          <span>Still processing...</span>
                        </div>
                        <div className="image-overlay-icon">
                          <svg width="24" height="24" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
                            <path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z" stroke="currentColor" strokeWidth="2"/>
                            <circle cx="12" cy="12" r="3" stroke="currentColor" strokeWidth="2"/>
                          </svg>
                        </div>
                      </>
                    )}
                    
                    <div className="image-overlay">
                      <button 
                        className="delete-btn"
                        onClick={(e) => {
                          e.stopPropagation();
                          deleteImage(image.id, image.originalKey);
                        }}
                        disabled={deleting.has(image.id)}
                        title="Delete image"
                      >
                        {deleting.has(image.id) ? (
                          <div className="spinner small"></div>
                        ) : (
                          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
                            <path d="M3 6h18M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
                          </svg>
                        )}
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
                    {image.realUpload && (
                      <div className="upload-badge">
                        <span>✓ Real Upload</span>
                      </div>
                    )}
                  </div>
                </div>
              ))}
            </div>
          )}
        </section>
      </main>
      
      {/* Image Modal */}
      <ImageModal image={selectedImage} onClose={handleCloseModal} />
      
      <DebugInfo />
    </div>
  );
}

// Helper function needs to be outside the component to avoid re-declaration
function formatFileSize(bytes) {
  if (bytes === 0) return '0 Bytes';
  const k = 1024;
  const sizes = ['Bytes', 'KB', 'MB', 'GB'];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
}

export default App;