/**
 * Firebase Cloud Functions for ChefKart Push Notifications
 *
 * Deploy with: firebase deploy --only functions
 *
 * These functions automatically send push notifications when:
 * - New booking request is created
 * - Request is accepted/rejected
 * - Booking is cancelled
 * - Chat message is sent
 */

const functions = require('firebase-functions');
const admin = require('firebase-admin');

admin.initializeApp();

const db = admin.firestore();
const messaging = admin.messaging();

// ==========================================
// HELPER FUNCTION - Send Push Notification
// ==========================================

async function sendPushNotification(userId, title, body, data = {}) {
  try {
    // Get user's FCM token
    const userDoc = await db.collection('users').doc(userId).get();
    const fcmToken = userDoc.data()?.fcmToken;

    if (!fcmToken) {
      console.log(`No FCM token for user ${userId}`);
      return false;
    }

    // Send notification
    const message = {
      notification: {
        title: title,
        body: body,
      },
      data: {
        ...data,
        click_action: 'FLUTTER_NOTIFICATION_CLICK',
      },
      token: fcmToken,
      android: {
        notification: {
          channelId: 'chef_kart_channel',
          priority: 'high',
          sound: 'default',
        },
      },
      apns: {
        payload: {
          aps: {
            sound: 'default',
            badge: 1,
          },
        },
      },
    };

    await messaging.send(message);
    console.log(`Notification sent to ${userId}: ${title}`);
    return true;
  } catch (error) {
    console.error('Error sending notification:', error);
    return false;
  }
}

// ==========================================
// TRIGGER: New Booking Request Created
// ==========================================

exports.onNewBookingRequest = functions.firestore
  .document('bookingRequests/{requestId}')
  .onCreate(async (snapshot, context) => {
    const request = snapshot.data();
    const requestId = context.params.requestId;

    // Notify chef about new request
    await sendPushNotification(
      request.chefId,
      'New Booking Request! 🎉',
      `${request.customerName} wants to book you for ${request.date}`,
      {
        type: 'new_request',
        screen: 'chef_requests',
        requestId: requestId,
      }
    );

    // Also save to notifications collection for in-app display
    await db.collection('notifications').add({
      userId: request.chefId,
      type: 'new_request',
      title: 'New Booking Request! 🎉',
      body: `${request.customerName} wants to book you for ${request.date}`,
      data: { screen: 'chef_requests', requestId: requestId },
      read: false,
      sent: true,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return null;
  });

// ==========================================
// TRIGGER: Booking Request Status Changed
// ==========================================

exports.onRequestStatusChange = functions.firestore
  .document('bookingRequests/{requestId}')
  .onUpdate(async (change, context) => {
    const before = change.before.data();
    const after = change.after.data();
    const requestId = context.params.requestId;

    // Only process if status changed
    if (before.status === after.status) return null;

    const newStatus = after.status;

    // Request Accepted
    if (newStatus === 'accepted' && before.status === 'pending') {
      await sendPushNotification(
        after.customerId,
        'Booking Confirmed! ✅',
        `${after.chefName} has accepted your booking for ${after.date}`,
        {
          type: 'request_accepted',
          screen: 'booking_details',
          requestId: requestId,
        }
      );

      await db.collection('notifications').add({
        userId: after.customerId,
        type: 'request_accepted',
        title: 'Booking Confirmed! ✅',
        body: `${after.chefName} has accepted your booking for ${after.date}`,
        data: { screen: 'booking_details', requestId: requestId },
        read: false,
        sent: true,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    // Request Rejected
    if (newStatus === 'rejected' && before.status === 'pending') {
      await sendPushNotification(
        after.customerId,
        'Chef Unavailable',
        `${after.chefName} is unavailable. Try another chef!`,
        {
          type: 'request_rejected',
          screen: 'find_chefs',
          requestId: requestId,
        }
      );

      await db.collection('notifications').add({
        userId: after.customerId,
        type: 'request_rejected',
        title: 'Chef Unavailable',
        body: `${after.chefName} is unavailable. Try another chef!`,
        data: { screen: 'find_chefs', requestId: requestId },
        read: false,
        sent: true,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    // Cancelled by Customer
    if (newStatus === 'cancelled_by_customer') {
      await sendPushNotification(
        after.chefId,
        'Booking Cancelled',
        `${after.customerName} has cancelled the booking for ${after.date}`,
        {
          type: 'booking_cancelled_by_customer',
          screen: 'chef_bookings',
          requestId: requestId,
        }
      );

      await db.collection('notifications').add({
        userId: after.chefId,
        type: 'booking_cancelled_by_customer',
        title: 'Booking Cancelled',
        body: `${after.customerName} has cancelled the booking for ${after.date}`,
        data: { screen: 'chef_bookings', requestId: requestId },
        read: false,
        sent: true,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    // Cancelled by Chef
    if (newStatus === 'cancelled_by_chef') {
      await sendPushNotification(
        after.customerId,
        'Booking Cancelled by Chef',
        `${after.chefName} had to cancel. Please try another chef.`,
        {
          type: 'booking_cancelled_by_chef',
          screen: 'find_chefs',
          requestId: requestId,
        }
      );

      await db.collection('notifications').add({
        userId: after.customerId,
        type: 'booking_cancelled_by_chef',
        title: 'Booking Cancelled by Chef',
        body: `${after.chefName} had to cancel. Please try another chef.`,
        data: { screen: 'find_chefs', requestId: requestId },
        read: false,
        sent: true,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    // Completed
    if (newStatus === 'completed') {
      await sendPushNotification(
        after.customerId,
        'Service Completed! 🌟',
        `How was your experience with ${after.chefName}? Leave a review!`,
        {
          type: 'booking_completed',
          screen: 'leave_review',
          requestId: requestId,
        }
      );

      await db.collection('notifications').add({
        userId: after.customerId,
        type: 'booking_completed',
        title: 'Service Completed! 🌟',
        body: `How was your experience with ${after.chefName}? Leave a review!`,
        data: { screen: 'leave_review', requestId: requestId },
        read: false,
        sent: true,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    return null;
  });

// ==========================================
// TRIGGER: New Chat Message
// ==========================================

exports.onNewChatMessage = functions.firestore
  .document('chats/{chatId}/messages/{messageId}')
  .onCreate(async (snapshot, context) => {
    const message = snapshot.data();
    const chatId = context.params.chatId;

    // Get chat participants
    const chatDoc = await db.collection('chats').doc(chatId).get();
    const chatData = chatDoc.data();

    if (!chatData) return null;

    // Determine recipient
    const recipientId = message.senderId === chatData.customerId
      ? chatData.chefId
      : chatData.customerId;

    // Get sender name
    const senderDoc = await db.collection('users').doc(message.senderId).get();
    const senderName = senderDoc.data()?.name || 'Someone';

    // Send notification
    await sendPushNotification(
      recipientId,
      senderName,
      message.text.length > 50
        ? message.text.substring(0, 50) + '...'
        : message.text,
      {
        type: 'chat_message',
        screen: 'chat',
        chatId: chatId,
      }
    );

    return null;
  });

// ==========================================
// SCHEDULED: Clean up old notifications (runs daily)
// ==========================================

exports.cleanupOldNotifications = functions.pubsub
  .schedule('every 24 hours')
  .onRun(async (context) => {
    const cutoffDate = new Date();
    cutoffDate.setDate(cutoffDate.getDate() - 30); // 30 days old

    const snapshot = await db.collection('notifications')
      .where('createdAt', '<', cutoffDate)
      .get();

    const batch = db.batch();
    snapshot.docs.forEach((doc) => {
      batch.delete(doc.ref);
    });

    await batch.commit();
    console.log(`Deleted ${snapshot.docs.length} old notifications`);
    return null;
  });

// ==========================================
// SCHEDULED: Expire old pending requests (runs every 5 minutes)
// ==========================================

exports.expirePendingRequests = functions.pubsub
  .schedule('every 5 minutes')
  .onRun(async (context) => {
    const cutoffTime = new Date();
    cutoffTime.setMinutes(cutoffTime.getMinutes() - 30); // 30 minutes old

    const snapshot = await db.collection('bookingRequests')
      .where('status', '==', 'pending')
      .where('createdAt', '<', cutoffTime)
      .get();

    const batch = db.batch();
    for (const doc of snapshot.docs) {
      batch.update(doc.ref, {
        status: 'expired',
        respondedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      // Notify customer about expiry
      const request = doc.data();
      await sendPushNotification(
        request.customerId,
        'Request Expired',
        `Your booking request to ${request.chefName} has expired. Try another chef!`,
        {
          type: 'request_expired',
          screen: 'find_chefs',
          requestId: doc.id,
        }
      );
    }

    await batch.commit();
    console.log(`Expired ${snapshot.docs.length} pending requests`);
    return null;
  });

// ==========================================
// INDRIVE-STYLE DEAL NEGOTIATION FUNCTIONS
// ==========================================

// TRIGGER: New Broadcast Cooking Request Created
exports.onNewCookingRequest = functions.firestore
  .document('cookingRequests/{requestId}')
  .onCreate(async (snapshot, context) => {
    const request = snapshot.data();
    const requestId = context.params.requestId;

    console.log(`New cooking request created: ${requestId}`);

    // Get all available chefs
    const chefsQuery = await db.collection('users')
      .where('role', '==', 'chef')
      .where('isAvailable', '==', true)
      .get();

    const customerLocation = request.customerLocation;
    const broadcastRadius = request.broadcastRadiusKm || 10;

    let notifiedCount = 0;

    for (const chefDoc of chefsQuery.docs) {
      const chefData = chefDoc.data();
      const chefId = chefDoc.id;

      // Skip if chef doesn't have location
      if (!chefData.lat || !chefData.lng) continue;

      // Calculate distance if customer location available
      if (customerLocation) {
        const distance = calculateDistance(
          customerLocation.latitude,
          customerLocation.longitude,
          chefData.lat,
          chefData.lng
        );

        // Skip if outside broadcast radius
        if (distance > broadcastRadius) continue;
      }

      // Send push notification to chef
      await sendPushNotification(
        chefId,
        'New Cooking Request! 🍳',
        `${request.customerName} is looking for a chef - Rs. ${request.offeredPrice}`,
        {
          type: 'new_broadcast_request',
          screen: 'broadcast_requests',
          requestId: requestId,
        }
      );

      // Save in-app notification
      await db.collection('notifications').add({
        userId: chefId,
        type: 'new_broadcast_request',
        title: 'New Cooking Request! 🍳',
        body: `${request.customerName} is looking for a chef for ${request.date}`,
        data: { screen: 'broadcast_requests', requestId: requestId },
        read: false,
        sent: true,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      notifiedCount++;
    }

    console.log(`Notified ${notifiedCount} chefs about request ${requestId}`);
    return null;
  });

// TRIGGER: New Chef Offer Created
exports.onNewChefOffer = functions.firestore
  .document('chefOffers/{offerId}')
  .onCreate(async (snapshot, context) => {
    const offer = snapshot.data();
    const offerId = context.params.offerId;

    // Get the cooking request
    const requestDoc = await db.collection('cookingRequests').doc(offer.requestId).get();
    if (!requestDoc.exists) return null;

    const request = requestDoc.data();

    // Determine notification text based on offer type
    const isCounterOffer = offer.offerType === 'counter';
    const title = isCounterOffer ? 'New Counter Offer! 💰' : 'Chef Accepted Your Price! ✅';
    const body = isCounterOffer
      ? `${offer.chefName} offers Rs. ${offer.offeredPrice} (your price: Rs. ${offer.originalPrice})`
      : `${offer.chefName} accepted Rs. ${offer.offeredPrice}`;

    // Notify customer
    await sendPushNotification(
      request.customerId,
      title,
      body,
      {
        type: 'new_chef_offer',
        screen: 'view_offers',
        requestId: offer.requestId,
        offerId: offerId,
      }
    );

    // Save in-app notification
    await db.collection('notifications').add({
      userId: request.customerId,
      type: 'new_chef_offer',
      title: title,
      body: body,
      data: { screen: 'view_offers', requestId: offer.requestId, offerId: offerId },
      read: false,
      sent: true,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return null;
  });

// TRIGGER: Chef Offer Status Changed
exports.onChefOfferStatusChange = functions.firestore
  .document('chefOffers/{offerId}')
  .onUpdate(async (change, context) => {
    const before = change.before.data();
    const after = change.after.data();
    const offerId = context.params.offerId;

    if (before.status === after.status) return null;

    const newStatus = after.status;
    const chefId = after.chefId;

    // Offer Accepted - Chef won the deal!
    if (newStatus === 'accepted') {
      await sendPushNotification(
        chefId,
        'Deal Confirmed! 🎉',
        `Customer confirmed your offer of Rs. ${after.offeredPrice}. Chat is now enabled!`,
        {
          type: 'offer_accepted',
          screen: 'chef_bookings',
          requestId: after.requestId,
          offerId: offerId,
        }
      );

      await db.collection('notifications').add({
        userId: chefId,
        type: 'offer_accepted',
        title: 'Deal Confirmed! 🎉',
        body: `Customer confirmed your offer. Chat is now enabled!`,
        data: { screen: 'chef_bookings', requestId: after.requestId },
        read: false,
        sent: true,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    // Offer Rejected - Customer selected another chef
    if (newStatus === 'rejected') {
      await sendPushNotification(
        chefId,
        'Offer Not Selected',
        'Customer selected another chef for this request.',
        {
          type: 'offer_rejected',
          screen: 'broadcast_requests',
          requestId: after.requestId,
        }
      );

      await db.collection('notifications').add({
        userId: chefId,
        type: 'offer_rejected',
        title: 'Offer Not Selected',
        body: 'Customer selected another chef for this request.',
        data: { screen: 'broadcast_requests', requestId: after.requestId },
        read: false,
        sent: true,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    // Offer Expired
    if (newStatus === 'expired') {
      await sendPushNotification(
        chefId,
        'Offer Expired',
        'The cooking request has expired.',
        {
          type: 'offer_expired',
          screen: 'broadcast_requests',
          requestId: after.requestId,
        }
      );
    }

    return null;
  });

// TRIGGER: Cooking Request Status Changed
exports.onCookingRequestStatusChange = functions.firestore
  .document('cookingRequests/{requestId}')
  .onUpdate(async (change, context) => {
    const before = change.before.data();
    const after = change.after.data();
    const requestId = context.params.requestId;

    if (before.status === after.status) return null;

    const newStatus = after.status;

    // Request Confirmed
    if (newStatus === 'confirmed') {
      // Notify customer about successful confirmation
      await sendPushNotification(
        after.customerId,
        'Chef Confirmed! 🎉',
        `${after.confirmedChefName} is your chef. You can now chat!`,
        {
          type: 'request_confirmed',
          screen: 'customer_bookings',
          requestId: requestId,
        }
      );

      // Expire all pending offers for this request
      const pendingOffers = await db.collection('chefOffers')
        .where('requestId', '==', requestId)
        .where('status', '==', 'pending')
        .get();

      const batch = db.batch();
      for (const offerDoc of pendingOffers.docs) {
        // Skip the confirmed offer
        if (offerDoc.id === after.confirmedOfferId) continue;

        batch.update(offerDoc.ref, {
          status: 'rejected',
          respondedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    }

    // Request Expired
    if (newStatus === 'expired') {
      await sendPushNotification(
        after.customerId,
        'Request Expired',
        'No chef was confirmed in time. Please try again.',
        {
          type: 'request_expired',
          screen: 'create_request',
          requestId: requestId,
        }
      );

      // Expire all related offers
      const offers = await db.collection('chefOffers')
        .where('requestId', '==', requestId)
        .where('status', '==', 'pending')
        .get();

      const batch = db.batch();
      for (const offerDoc of offers.docs) {
        batch.update(offerDoc.ref, {
          status: 'expired',
          respondedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    }

    // Request Cancelled
    if (newStatus === 'cancelled') {
      // Notify all chefs who sent offers
      const offers = await db.collection('chefOffers')
        .where('requestId', '==', requestId)
        .get();

      for (const offerDoc of offers.docs) {
        const offer = offerDoc.data();
        await sendPushNotification(
          offer.chefId,
          'Request Cancelled',
          'Customer cancelled the cooking request.',
          {
            type: 'request_cancelled',
            screen: 'broadcast_requests',
            requestId: requestId,
          }
        );
      }
    }

    return null;
  });

// SCHEDULED: Expire old cooking requests (runs every 2 minutes)
exports.expireCookingRequests = functions.pubsub
  .schedule('every 2 minutes')
  .onRun(async (context) => {
    const now = admin.firestore.Timestamp.now();

    // Find pending requests that have expired
    const snapshot = await db.collection('cookingRequests')
      .where('status', '==', 'pending')
      .where('expiresAt', '<', now)
      .get();

    if (snapshot.empty) {
      console.log('No expired cooking requests found');
      return null;
    }

    const batch = db.batch();

    for (const doc of snapshot.docs) {
      // Update request to expired
      batch.update(doc.ref, {
        status: 'expired',
      });

      // Get related offers and expire them
      const offers = await db.collection('chefOffers')
        .where('requestId', '==', doc.id)
        .where('status', '==', 'pending')
        .get();

      for (const offerDoc of offers.docs) {
        batch.update(offerDoc.ref, {
          status: 'expired',
          respondedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }

      // Notify customer
      const request = doc.data();
      await sendPushNotification(
        request.customerId,
        'Request Expired ⏰',
        'Your cooking request expired. Try again with a longer time window.',
        {
          type: 'request_expired',
          screen: 'create_request',
          requestId: doc.id,
        }
      );
    }

    await batch.commit();
    console.log(`Expired ${snapshot.docs.length} cooking requests`);
    return null;
  });

// HELPER: Calculate distance between two coordinates (Haversine formula)
function calculateDistance(lat1, lon1, lat2, lon2) {
  const earthRadius = 6371; // km
  const dLat = toRadians(lat2 - lat1);
  const dLon = toRadians(lon2 - lon1);
  const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(toRadians(lat1)) * Math.cos(toRadians(lat2)) *
    Math.sin(dLon / 2) * Math.sin(dLon / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return earthRadius * c;
}

function toRadians(degrees) {
  return degrees * Math.PI / 180;
}

