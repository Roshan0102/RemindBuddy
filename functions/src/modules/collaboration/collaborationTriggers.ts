import * as functions from "firebase-functions";
import { admin, db } from "../../config/firebase";
import { logNotification } from "../../utils/logger";

export const onCollaborationRequestCreated = functions.firestore
    .document('collaboration_requests/{requestId}')
    .onCreate(async (snapshot, context) => {
        const data = snapshot.data();
        if (!data) return;

        const { senderUsername, receiverUid, type, title } = data;
        if (!receiverUid) return;

        try {
            const usernameDoc = await db.collection("usernames").where("uid", "==", receiverUid).limit(1).get();
            if (usernameDoc.empty) {
                console.log(`No usernames document found for receiver UID ${receiverUid}`);
                return;
            }

            const token = usernameDoc.docs[0].data().fcmToken;
            if (!token) {
                console.log(`No FCM token found for receiver UID ${receiverUid}`);
                return;
            }

            const notifTitle = "Collaboration Request";
            const typeLabel = type === 'note' ? 'notes' : 'checklist';
            const body = `${senderUsername} is requesting collaboration for this ${typeLabel}: "${title}"`;

            await admin.messaging().send({
                token,
                notification: { 
                    title: notifTitle, 
                    body: body 
                },
                android: { 
                    notification: { 
                        channelId: "collaboration_channel",
                        tag: `collaboration_${context.params.requestId}`
                    } 
                },
                data: { 
                    type: "collaboration_request",
                    requestId: context.params.requestId,
                    collaborationType: type
                }
            });

            await logNotification(receiverUid, notifTitle, body, "COLLABORATION_REQUEST");
            console.log(`Successfully sent collaboration request notification to user ${receiverUid}`);
        } catch (error) {
            console.error("Failed to send collaboration request notification:", error);
        }
    });

export const onCollaborationRequestUpdated = functions.firestore
    .document('collaboration_requests/{requestId}')
    .onUpdate(async (change, context) => {
        const newData = change.after.data();
        const oldData = change.before.data();
        
        if (!newData || !oldData) return;
        
        // Check if status changed to approved
        if (newData.status === 'approved' && oldData.status !== 'approved') {
            const { senderUid, receiverUid, itemId, type } = newData;
            if (!senderUid || !receiverUid || !itemId || !type) return;
            
            try {
                const subcollection = type === 'note' ? 'notes' : 'checklists';
                const docRef = db.collection('users').doc(senderUid).collection(subcollection).doc(itemId);
                
                await db.runTransaction(async (transaction) => {
                    const docSnap = await transaction.get(docRef);
                    if (!docSnap.exists) {
                        console.log(`Document users/${senderUid}/${subcollection}/${itemId} not found`);
                        return;
                    }
                    
                    const docData = docSnap.data() || {};
                    let sharedWith = docData.sharedWith || [];
                    if (!sharedWith.includes(receiverUid)) {
                        sharedWith.push(receiverUid);
                    }
                    
                    transaction.update(docRef, {
                        sharedWith: sharedWith,
                        ownerUid: senderUid
                    });
                });
                
                console.log(`Successfully added collaborator ${receiverUid} to document ${itemId}`);
            } catch (error) {
                console.error("Failed to update collaborator on document:", error);
            }
        }
    });
