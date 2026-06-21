// Firebase Admin init + Firestore handle. Imported (transitively) by every domain
// module, so initializeApp() runs exactly once here before getFirestore().

import { initializeApp } from 'firebase-admin/app';
import { FieldValue, Timestamp, getFirestore } from 'firebase-admin/firestore';

initializeApp();

export const db = getFirestore();
export { FieldValue, Timestamp };
